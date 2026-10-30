import XCTest
import FirebaseAuth
@testable import ArboreUi

// Génération des vignettes du catalogue, sans passer par l'app. (#524, #609)
//
// Les vignettes servies portent le repère violet et le cadrage studio de
// `PlantThumbnailRenderer` — donc de RealityKit, pas d'`usdrecord`. Les
// régénérer demandait jusqu'ici un écran caché derrière `#if DEBUG`, absent
// d'une build TestFlight, et la route de téléversement exige un compte
// administrateur.
//
// Ce test pilote le MÊME renderer depuis le simulateur et écrit les PNG sur le
// disque de la machine. Le déploiement se fait ensuite en copiant les fichiers
// dans le répertoire servi — pas d'écran, pas de compte admin.
//
// Il ne tourne QUE si on le demande, par une variable d'environnement : la CI
// ne doit pas rendre 123 plantes à chaque poussée.
//
//   TEST_RUNNER_ARBORE_VIGNETTES_DIR=/chemin/de/sortie \
//   xcodebuild test -workspace ArboreUi.xcworkspace -scheme "ArboreUi Dev" \
//     -configuration Dev -destination 'platform=iOS Simulator,name=iPhone 17' \
//     -only-testing:ArboreUiTests/GenerationVignettesTests
//
// Trois pièges dans cette ligne, et chacun a coûté une passe.
//
// 1. Le préfixe `TEST_RUNNER_` n'est pas décoratif. `xcodebuild` ne transmet
//    PAS l'environnement du shell au processus de test ; c'est ce préfixe qui
//    le fait. Sans lui, la variable est absente et le test se saute en
//    silence — il rend « Skipped », pas une erreur.
// 2. Le schéma décide de l'environnement. `ArboreUi` compile avec
//    `api.arbore.app` même en Debug : seul `ArboreUi Dev` lit
//    `Secrets.dev.xcconfig`. Au mauvais schéma, on rend les vignettes du
//    catalogue de PRODUCTION.
// 3. Pas de `CODE_SIGNING_ALLOWED=NO`. Le SDK Firebase écrit sa session dans
//    le keychain, et un bundle non signé n'en a pas le droit ; sans session,
//    les 123 modèles reviennent en 401. Voir `jetonInvite()`.
//
// `TEST_RUNNER_ARBORE_VIGNETTES_PLANTES` limite à une liste d'identifiants
// séparés par des virgules, pour reprendre une plante sans refaire les 123.

final class GenerationVignettesTests: XCTestCase {

    /// Répartition du travail : rendre une plante coûte plusieurs secondes, et
    /// le test doit rester interruptible sans laisser le simulateur occupé.
    private let delaiParPlante: TimeInterval = 90

    func testGenererLesVignettes() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let sortie = env["ARBORE_VIGNETTES_DIR"], !sortie.isEmpty else {
            throw XCTSkip("ARBORE_VIGNETTES_DIR absent — génération non demandée")
        }
        try FileManager.default.createDirectory(
            atPath: sortie, withIntermediateDirectories: true)

        let plantes = try await catalogue()
        XCTAssertFalse(plantes.isEmpty, "catalogue vide : rien à rendre")

        let filtre = (env["ARBORE_VIGNETTES_PLANTES"] ?? "")
            .split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let aFaire = filtre.isEmpty ? plantes : plantes.filter { filtre.contains($0.id) }

        let renderer = await PlantThumbnailRenderer()
        var rendues = 0
        var echecs: [String] = []

        for plante in aFaire {
            do {
                let image = try await rendre(plante, avec: renderer)
                guard let rendu = image.pngData() else {
                    echecs.append("\(plante.name) : encodage PNG"); continue
                }
                // Au gabarit servi, et par le MÊME code que l'envoi depuis
                // l'app. Le rendu brut fait 3072×3840 pour une dizaine de
                // mégaoctets — au-delà des 8 Mo du backend, et sans rapport
                // avec les 720×900 des 123 vignettes en service.
                let png = try ReductionVignette.reduire(png: rendu)
                // Nommé par identifiant de fiche, comme la route qui les sert :
                // `/models/thumbnails/<plantId>.png`.
                let chemin = (sortie as NSString).appendingPathComponent("\(plante.id).png")
                try png.write(to: URL(fileURLWithPath: chemin))
                rendues += 1
                print("🖼️ \(plante.name) → \(chemin) (\(png.count / 1024) ko)")
            } catch {
                echecs.append("\(plante.name) : \(error)")
            }
        }

        print("🖼️ \(rendues) vignettes écrites dans \(sortie), \(echecs.count) échecs")
        for e in echecs { print("   ⚠️ \(e)") }

        // Les raisons vont dans le MESSAGE d'assertion, pas seulement dans
        // `print` : la sortie standard du processus de test n'apparaît pas dans
        // le journal de `xcodebuild`, si bien qu'un échec se lisait
        // « ("0") is not greater than ("0") » et rien d'autre. Un test qu'on
        // lance à la main doit livrer sa cause dans ce qu'il affiche.
        XCTAssertGreaterThan(
            rendues, 0,
            "aucune vignette produite sur \(aFaire.count) tentées. "
                + "Premiers échecs : " + echecs.prefix(3).joined(separator: " ||| "))

        if !echecs.isEmpty {
            print("🖼️ \(echecs.count) échecs sur \(aFaire.count)")
        }
    }

    // MARK: - Rendu d'une plante

    /// Rend une plante, pot compris quand elle est recoupée.
    ///
    /// Le pot passe par `potEtPose()`, le même accesseur que l'AR : une
    /// vignette et un rendu AR doivent montrer le même objet, sans quoi le
    /// catalogue annonce autre chose que ce qu'on pose.
    @MainActor
    private func rendre(_ plante: Plant,
                        avec renderer: PlantThumbnailRenderer) async throws -> UIImage {
        let modele = try await plante.getModelURL()

        var pot: (url: URL, pose: PotPlacement)?
        if let lie = plante.potEtPose() {
            let url = try await ModelCacheManager.shared.getModelURL(
                for: lie.pot.modelURL, version: lie.pot.version)
            pot = (url, lie.pose)
        }

        return try await withCheckedThrowingContinuation { suite in
            renderer.render(usdzURL: modele, upAxis: plante.upAxis, pot: pot) { image in
                if let image { suite.resume(returning: image) }
                else { suite.resume(throwing: ErreurVignette.rendu) }
            }
        }
    }

    /// Les échecs de ce test portent leur raison.
    ///
    /// La version d'avant rendait `case catalogue` sans rien : l'échec
    /// s'affichait `caught error: "catalogue"`, ce qui ne dit ni le code HTTP
    /// ni ce que le serveur a répondu. Un test d'outillage qu'on lance à la
    /// main doit se diagnostiquer depuis sa seule sortie.
    private enum ErreurVignette: Error, CustomStringConvertible {
        case rendu
        case catalogue(statut: Int?, detail: String)
        case session(detail: String)

        var description: String {
            switch self {
            case .rendu:
                return "le renderer n'a pas rendu d'image"
            case .catalogue(let statut, let detail):
                let code = statut.map { "HTTP \($0)" } ?? "sans réponse HTTP"
                return "catalogue illisible (\(code)) : \(detail)"
            case .session(let detail):
                return "session Firebase impossible — le bundle est-il signé ? : \(detail)"
            }
        }
    }

    // MARK: - Catalogue

    /// Le catalogue tel que l'app le reçoit, pour que les vignettes portent
    /// exactement les modèles servis — pot compris.
    private func catalogue() async throws -> [Plant] {
        let base = NetworkManager.shared.baseURL
        guard let url = URL(string: "\(base)/plants") else {
            throw ErreurVignette.catalogue(statut: nil, detail: "URL invalide : \(base)/plants")
        }

        // Une session est OBLIGATOIRE, et c'est ce qui manquait.
        //
        // `/plants` est derrière `protected`. Le premier jet posait l'en-tête
        // `Authorization` avec un `try?`, si bien qu'un test sans utilisateur
        // connecté — c'est-à-dire tous — partait sans jeton, prenait un 401 et
        // échouait sur un `ErreurVignette.catalogue` muet. Trois quarts d'heure
        // pour lire « caught error: "catalogue" » dans un bundle de résultats.
        let jeton = try await jetonInvite()

        var requete = URLRequest(url: url)
        requete.setValue(NetworkManager.shared.apiKey, forHTTPHeaderField: "X-API-Key")
        requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")

        let (donnees, reponse) = try await URLSession.shared.data(for: requete)
        guard let http = reponse as? HTTPURLResponse else {
            throw ErreurVignette.catalogue(statut: nil, detail: "réponse non HTTP")
        }
        guard http.statusCode == 200 else {
            // Le corps dit lequel des deux en-têtes a été refusé, et sans lui
            // un 401 et un 403 se ressemblent.
            let corps = String(decoding: donnees.prefix(200), as: UTF8.self)
            throw ErreurVignette.catalogue(statut: http.statusCode, detail: corps)
        }
        return try JSONDecoder().decode([Plant].self, from: donnees)
    }

    /// Ouvre une session Firebase invité, par le SDK, et rend son jeton.
    ///
    /// **Le SDK est obligatoire, et le REST ne peut pas le remplacer.** J'ai
    /// essayé : demander un jeton anonyme à Identity Toolkit évite bien le
    /// keychain, et le catalogue se lit. Mais rendre une plante télécharge son
    /// modèle par `ModelCacheManager`, qui redemande un jeton à
    /// `NetworkManager.getFirebaseToken()` — lequel lit
    /// `Auth.auth().currentUser`. Sans session SDK, ce `currentUser` est nil,
    /// l'en-tête `Authorization` n'est pas posé, et les 123 modèles reviennent
    /// en 401. Un jeton dans une variable n'atteint pas ce chemin-là.
    ///
    /// Conséquence pratique : ce test exige un bundle **signé**. Construit avec
    /// `CODE_SIGNING_ALLOWED=NO`, le SDK ne peut pas écrire sa session —
    /// `SecItemAdd (-34018) A required entitlement isn't present` — et rien ne
    /// se rend. L'invocation en tête de fichier ne porte donc pas ce drapeau.
    private func jetonInvite() async throws -> String {
        if Auth.auth().currentUser == nil {
            do {
                try await withCheckedThrowingContinuation {
                    (suite: CheckedContinuation<Void, Error>) in
                    GuestSession.signIn { resultat in
                        switch resultat {
                        case .success: suite.resume()
                        case .failure(let erreur): suite.resume(throwing: erreur)
                        }
                    }
                }
            } catch {
                throw ErreurVignette.session(detail: "\(error)")
            }
        }
        do {
            return try await NetworkManager.shared.getFirebaseToken()
        } catch {
            throw ErreurVignette.session(detail: "jeton indisponible : \(error)")
        }
    }
}
