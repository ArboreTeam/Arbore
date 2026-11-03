//
//  ArboreUiTests.swift
//  ArboreUiTests
//
//  Created by Hugo Rath on 14/03/2025.
//

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
        timeout: TimeInterval = 7
    ) throws {
        let adresse = AppConfig.baseURL

        guard let url = URL(string: "\(adresse)/health") else {
            throw BackendPromisMaisAbsent(
                suite: suite, adresse: adresse, detail: "URL de backend invalide")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout - 2

        let verrou = DispatchSemaphore(value: 0)
        var code: Int?
        var echec: Error?

        URLSession.shared.dataTask(with: request) { _, response, error in
            code = (response as? HTTPURLResponse)?.statusCode
            echec = error
            verrou.signal()
        }.resume()

        guard verrou.wait(timeout: .now() + timeout) == .success else {
            throw BackendPromisMaisAbsent(
                suite: suite, adresse: adresse,
                detail: "aucune réponse de /health en \(Int(timeout)) s")
        }
        if let echec {
            throw BackendPromisMaisAbsent(
                suite: suite, adresse: adresse,
                detail: "échec réseau sur /health (\(echec.localizedDescription))")
        }
        guard code == 200 else {
            throw BackendPromisMaisAbsent(
                suite: suite, adresse: adresse,
                detail: "/health a rendu \(code.map(String.init) ?? "aucun statut")")
        }
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
