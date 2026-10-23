import XCTest
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
//   ARBORE_VIGNETTES_DIR=/chemin/de/sortie \
//   xcodebuild test -scheme ArboreUi \
//     -only-testing:ArboreUiTests/GenerationVignettesTests
//
// `ARBORE_VIGNETTES_PLANTES` limite à une liste d'identifiants séparés par des
// virgules, pour reprendre une plante sans refaire les 123.

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
                guard let png = image.pngData() else {
                    echecs.append("\(plante.name) : encodage PNG"); continue
                }
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
        XCTAssertGreaterThan(rendues, 0, "aucune vignette produite")
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

    private enum ErreurVignette: Error { case rendu, catalogue }

    // MARK: - Catalogue

    /// Le catalogue tel que l'app le reçoit, pour que les vignettes portent
    /// exactement les modèles servis — pot compris.
    private func catalogue() async throws -> [Plant] {
        let base = NetworkManager.shared.baseURL
        guard let url = URL(string: "\(base)/plants") else { throw ErreurVignette.catalogue }
        var requete = URLRequest(url: url)
        requete.setValue(NetworkManager.shared.apiKey, forHTTPHeaderField: "X-API-Key")
        if let jeton = try? await NetworkManager.shared.getFirebaseToken() {
            requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
        }
        let (donnees, reponse) = try await URLSession.shared.data(for: requete)
        guard let http = reponse as? HTTPURLResponse, http.statusCode == 200 else {
            throw ErreurVignette.catalogue
        }
        return try JSONDecoder().decode([Plant].self, from: donnees)
    }
}
