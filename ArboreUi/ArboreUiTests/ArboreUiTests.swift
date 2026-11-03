//
//  ArboreUiTests.swift
//  ArboreUiTests
//
//  Created by Hugo Rath on 14/03/2025.
//

import FirebaseAuth
import FirebaseCore
import Testing
import XCTest
@testable import ArboreUi

/// Portillon des tests d'intégration « en vrai » — ceux qui frappent le
/// backend et Firebase. (#725 point 3)
///
/// ## Le drapeau est une PROMESSE, pas une préférence
///
/// `requireEnabled()` demande à l'opérateur d'affirmer qu'un backend est
/// disponible. Tant qu'il ne l'affirme pas, les tests se sautent : c'est le
/// bon défaut sur une machine de développement, où personne ne veut du rouge
/// pour une pile qui ne tourne pas.
///
/// Mais une fois le drapeau posé, un backend injoignable n'est plus une
/// circonstance, c'est une **contradiction** : on a promis une pile, elle
/// n'est pas là. Ça doit échouer.
///
/// Avant le 2026-11-03, les deux cas se sautaient. Le second produisait donc
/// un vert qui ne prouvait rien — pire qu'un test absent, puisqu'il se compte
/// comme une couverture. Relevé sur une passe locale : **26 tests sautés**
/// sur les quatre suites d'intégration.
///
/// ## Et le drapeau n'était posé nulle part
///
/// Vérifié le 2026-11-03 : `ARBORE_RUN_LIVE_INTEGRATION_TESTS` n'apparaissait
/// dans aucun workflow ni aucun script. Les suites ne se sautaient donc pas
/// « quand le backend est injoignable » — elles se sautaient **toujours**, et
/// le contrôle de disponibilité ci-dessous n'avait jamais été exécuté.
///
/// ## Le préfixe `TEST_RUNNER_`
///
/// `xcodebuild` ne transmet au processus de test que les variables préfixées
/// `TEST_RUNNER_`, qu'il retire au passage. La CI pose donc
/// `TEST_RUNNER_ARBORE_RUN_LIVE_INTEGRATION_TESTS`, et le test lit
/// `ARBORE_RUN_LIVE_INTEGRATION_TESTS`. Oublier le préfixe est le piège
/// consigné en #694 : le test se saute, en silence, et on cherche ailleurs.
enum LiveIntegrationTestGate {
    static let environmentKey = "ARBORE_RUN_LIVE_INTEGRATION_TESTS"

    /// Erreur d'un backend promis mais absent. `LocalizedError` plutôt qu'un
    /// `XCTFail` : XCTest rapporte le message tel quel, et l'exécution du test
    /// s'arrête là où elle doit s'arrêter.
    struct BackendPromisMaisAbsent: LocalizedError {
        let suite: String
        let adresse: String
        let detail: String

        var errorDescription: String? {
            """
            [\(suite)] backend promis mais injoignable — \(detail) : \(adresse)

            \(LiveIntegrationTestGate.environmentKey)=1 affirme qu'un backend est \
            disponible. Ce test NE SE SAUTE PAS : un vert obtenu sans avoir \
            interrogé le backend ne prouverait rien.

            Ou bien démarrer la pile, ou bien retirer le drapeau — auquel cas \
            la suite se sautera, visiblement.
            """
        }
    }

    static func requireEnabled() throws {
        guard ProcessInfo.processInfo.environment[environmentKey] == "1" else {
            throw XCTSkip(
                "Live Firebase/backend integration test skipped. Set \(environmentKey)=1 and run with a signed test host."
            )
        }
    }

    /// Vérifie que `/health` répond 200, et **échoue** sinon.
    ///
    /// N'est atteignable qu'après `requireEnabled()`, donc la promesse est
    /// déjà faite quand on arrive ici. Le contrôle est synchrone par
    /// sémaphore plutôt que par `XCTestExpectation` : la fonction est
    /// statique, partagée par quatre suites, et n'a pas de `XCTestCase` sous
    /// la main.
    static func requireBackendReachable(
        suite: String,
        essais: Int = 3,
        delaiParEssai: TimeInterval = 10
    ) throws {
        let adresse = AppConfig.baseURL

        guard let url = URL(string: "\(adresse)/health") else {
            throw BackendPromisMaisAbsent(
                suite: suite, adresse: adresse, detail: "URL de backend invalide")
        }

        var dernierDetail = "aucune tentative"
        for essai in 1...max(essais, 1) {
            switch interrogerSante(url: url, delai: delaiParEssai) {
            case .success:
                return
            case .failure(let detail):
                dernierDetail = detail
                // Pause courte avant de réessayer : on attend un service qui
                // se réveille, pas un service en panne.
                if essai < essais { Thread.sleep(forTimeInterval: 2) }
            }
        }

        throw BackendPromisMaisAbsent(
            suite: suite, adresse: adresse,
            detail: "\(essais) tentative(s) sur /health, la dernière : \(dernierDetail)")
    }

    private enum ResultatDeSante {
        case success
        case failure(String)
    }

    /// Une interrogation de `/health`, synchrone par sémaphore.
    ///
    /// Plusieurs tentatives, et c'est délibéré. Le premier appel HTTPS d'une
    /// suite paie la résolution DNS, la poignée TLS et le réveil de
    /// Cloudflare ; sur un runner froid il a dépassé cinq secondes en CI le
    /// 2026-11-03, alors que les trois tests suivants de la même classe sont
    /// passés sans peine.
    ///
    /// Un portillon qui crie au backend absent pour une poignée de main lente
    /// devient la prochaine chose qu'on apprend à ignorer — exactement le
    /// défaut qu'il a été écrit pour corriger. Il doit distinguer « absent »
    /// de « lent ».
    private static func interrogerSante(url: URL, delai: TimeInterval) -> ResultatDeSante {
        var requete = URLRequest(url: url)
        requete.httpMethod = "GET"
        requete.timeoutInterval = delai

        let verrou = DispatchSemaphore(value: 0)
        var code: Int?
        var echec: Error?

        URLSession.shared.dataTask(with: requete) { _, reponse, erreur in
            code = (reponse as? HTTPURLResponse)?.statusCode
            echec = erreur
            verrou.signal()
        }.resume()

        guard verrou.wait(timeout: .now() + delai + 3) == .success else {
            return .failure("aucune réponse en \(Int(delai)) s")
        }
        if let echec {
            return .failure("échec réseau (\(echec.localizedDescription))")
        }
        guard code == 200 else {
            return .failure("/health a rendu \(code.map(String.init) ?? "aucun statut")")
        }
        return .success
    }

    // MARK: - Les deux identités que le backend distingue

    /// Pourquoi deux, et pourquoi ce n'est pas un choix de commodité.
    ///
    /// Depuis #377, une identité Firebase seule est un **invité**, et depuis
    /// #392 un email non vérifié est refusé sur toute route authentifiée sauf
    /// `POST /users` et `DELETE /users`. Les fixtures d'origine créaient un
    /// compte email/mot de passe jetable et ne vérifiaient jamais l'adresse :
    /// dix tests échouaient en `EMAIL_NOT_VERIFIED` le jour où ils ont enfin
    /// tourné (2026-11-03, #725).
    ///
    /// Le découpage qui suit est **forcé par les routes**, pas préféré :
    ///
    ///   - `/users/export`, `DELETE /users`, `/gardens`, `/plants`,
    ///     `/models/:filename` acceptent les invités. #393 l'a voulu ainsi :
    ///     un invité doit pouvoir exercer ses droits sans compte.
    ///   - `/consents` et `GET /users/:uid` les refusent, par conception. Les
    ///     tester en invité reviendrait à tester le refus, pas la fonction.
    ///
    /// Et le test de SUPPRESSION tranche à lui seul : il détruit le compte,
    /// donc il lui faut une identité jetable, donc non vérifiable, donc
    /// invitée. Aucun compte de longue durée ne peut jouer ce rôle.

    /// Ouvre une session **invitée** : une identité Firebase anonyme.
    ///
    /// Exempte du portillon d'email — un compte anonyme n'a pas d'adresse du
    /// tout — et c'est exactement le parcours que #391 a ouvert.
    @discardableResult
    static func ouvrirSessionInvitee() async throws -> FirebaseAuth.User {
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        if let courant = Auth.auth().currentUser { try? Auth.auth().signOut() ; _ = courant }
        return try await Auth.auth().signInAnonymously().user
    }

    /// Clé interne, requise pour provisionner un compte de test vérifié.
    ///
    /// Transmise par `TEST_RUNNER_ARBORE_INTERNAL_KEY`. Elle n'ouvre que les
    /// routes `/internal`, et seulement là où elle est posée : la production
    /// ne l'a pas, et y rend 503 (#696).
    static let cleInterne = "ARBORE_INTERNAL_KEY"

    /// Domaine réservé des comptes de test. RFC 2606 : `.test` n'est pas
    /// résoluble, donc aucune de ces adresses ne désigne une personne.
    static let domaineDeTest = "arbore.test"

    /// Ouvre une session **membre** : un compte jetable à email VÉRIFIÉ.
    ///
    /// Vérifier une adresse demande normalement une boîte mail, qu'aucun test
    /// ne peut automatiser. `POST /internal/test-accounts/verify` pose
    /// `emailVerified` via le SDK Admin — ce n'est pas une dérogation au
    /// portillon de #377 : le jeton émis ensuite porte réellement
    /// `email_verified: true`, et le contrôle s'applique normalement.
    ///
    /// Jetable, et non partagé : chaque exécution a son compte, donc aucun
    /// état ne s'accumule entre les passages, et le test de suppression RGPD
    /// peut détruire le sien sans gêner personne.
    ///
    /// Se saute — et le DIT — quand la clé interne n'est pas transmise. C'est
    /// une promesse distincte de celle du backend : le drapeau affirme qu'une
    /// pile répond, pas qu'on a de quoi provisionner un compte.
    @discardableResult
    static func ouvrirSessionMembre() async throws -> FirebaseAuth.User {
        let env = ProcessInfo.processInfo.environment
        guard let cle = env[cleInterne], !cle.isEmpty else {
            throw XCTSkip("""
                Clé interne absente : impossible de provisionner un compte de \
                test à email vérifié.

                Ces tests visent des routes fermées aux invités \
                (consentements, profil) et exigent donc une adresse VÉRIFIÉE. \
                Transmettre TEST_RUNNER_\(cleInterne) à xcodebuild, contre un \
                backend qui porte cette clé — la production ne la porte pas, \
                et y répondrait 503. Voir #725.
                """)
        }

        if FirebaseApp.app() == nil { FirebaseApp.configure() }
        if Auth.auth().currentUser != nil { try? Auth.auth().signOut() }

        let email = "test.membre.\(UUID().uuidString.lowercased())@\(domaineDeTest)"
        let identifiants = try await Auth.auth().createUser(
            withEmail: email, password: "TestMembre2026!")

        try await marquerLAdresseVerifiee(email: email, cleInterne: cle)

        // Le jeton DÉJÀ émis porte encore `email_verified: false` : la
        // revendication est figée à l'émission. Sans ce rafraîchissement
        // forcé, le backend refuserait en EMAIL_NOT_VERIFIED alors que
        // l'identité est bel et bien vérifiée — et on chercherait le défaut
        // du mauvais côté.
        try await identifiants.user.reload()
        let jeton = try await identifiants.user.getIDTokenResult(forcingRefresh: true)
        guard jeton.claims["email_verified"] as? Bool == true else {
            XCTFail("""
                L'adresse \(email) a été marquée vérifiée, mais le jeton \
                rafraîchi porte toujours email_verified = \
                \(String(describing: jeton.claims["email_verified"])). \
                Le backend refusera toute route authentifiée.
                """)
            throw XCTSkip("revendication non propagée")
        }
        return identifiants.user
    }

    /// Appelle la route interne qui pose `emailVerified`.
    private static func marquerLAdresseVerifiee(email: String, cleInterne cle: String) async throws {
        guard let url = URL(string: "\(AppConfig.baseURL)/internal/test-accounts/verify") else {
            throw BackendPromisMaisAbsent(
                suite: "provisionnement", adresse: AppConfig.baseURL,
                detail: "URL de la route interne invalide")
        }
        var requete = URLRequest(url: url)
        requete.httpMethod = "POST"
        requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requete.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        requete.setValue(cle, forHTTPHeaderField: "X-Arbore-Internal-Key")
        requete.httpBody = try JSONSerialization.data(withJSONObject: ["email": email])

        let (data, reponse) = try await URLSession.shared.data(for: requete)
        let statut = (reponse as? HTTPURLResponse)?.statusCode ?? -1
        if statut == 200 { return }

        let corps = String(data: data, encoding: .utf8) ?? "<illisible>"

        // 404 et 503 veulent dire « ce backend ne sait pas provisionner », pas
        // « le backend est absent ». La distinction est le contrat du
        // portillon : le drapeau promet une pile qui RÉPOND, et elle répond.
        //
        //   404 — le backend est antérieur à la route (#725). C'est le cas de
        //         la CI de la PR qui l'introduit : elle ne peut pas exiger
        //         d'un déploiement qu'il contienne du code pas encore fusionné.
        //   503 — la clé interne n'est pas posée sur cette pile. C'est l'état
        //         voulu en production (#696).
        //
        // Tout autre code EST un défaut : la route existe, elle a refusé.
        if statut == 404 || statut == 503 {
            throw XCTSkip("""
                Ce backend ne sait pas provisionner de compte vérifié — \
                POST /internal/test-accounts/verify a rendu \(statut).

                \(statut == 404
                    ? "La route n'y est pas encore déployée."
                    : "La clé interne n'y est pas posée, et c'est voulu en production.")

                Les tests « membre » se sautent donc ; les « invité » tournent.
                """)
        }

        throw BackendPromisMaisAbsent(
            suite: "provisionnement", adresse: AppConfig.baseURL,
            detail: "POST /internal/test-accounts/verify a rendu \(statut) — \(corps)")
    }

    /// Détruit le compte de test courant, données comprises.
    ///
    /// `DELETE /users` purge Mongo PUIS l'identité Firebase, en un geste —
    /// c'est le chemin de l'app elle-même. Supprimer seulement l'identité
    /// laisserait des documents sans propriétaire, que le job de
    /// réconciliation (#393) devrait ramasser plus tard : autant ne pas en
    /// créer la dette.
    ///
    /// Silencieuse sur l'échec : en `tearDown`, le compte peut déjà avoir été
    /// supprimé par le test lui-même.
    static func fermerEtDetruireLaSessionDeTest() async {
        defer { try? Auth.auth().signOut() }
        guard let utilisateur = Auth.auth().currentUser,
              let url = URL(string: "\(AppConfig.baseURL)/users"),
              let jeton = try? await utilisateur.getIDToken() else { return }

        var requete = URLRequest(url: url)
        requete.httpMethod = "DELETE"
        requete.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        requete.setValue("Bearer \(jeton)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: requete)
        try? await utilisateur.delete()
    }
}

struct ArboreUiTests {

    @Test func passwordPolicyRejectsMissingFields() {
        #expect(
            PasswordPolicy.validationError(
                currentPassword: "",
                newPassword: "Password2026!",
                confirmation: "Password2026!"
            ) == "CHANGE_PASSWORD_ERROR_REQUIRED"
        )
    }

    @Test func passwordPolicyRejectsMismatchAndReuse() {
        #expect(
            PasswordPolicy.validationError(
                currentPassword: "OldPassword2026!",
                newPassword: "NewPassword2026!",
                confirmation: "AnotherPassword2026!"
            ) == "CHANGE_PASSWORD_ERROR_MISMATCH"
        )
        #expect(
            PasswordPolicy.validationError(
                currentPassword: "SamePassword2026!",
                newPassword: "SamePassword2026!",
                confirmation: "SamePassword2026!"
            ) == "CHANGE_PASSWORD_ERROR_SAME"
        )
    }

    @Test func passwordPolicyAcceptsValidPassword() {
        #expect(
            PasswordPolicy.validationError(
                currentPassword: "OldPassword2026!",
                newPassword: "NewPassword2026!",
                confirmation: "NewPassword2026!"
            ) == nil
        )
    }

}
