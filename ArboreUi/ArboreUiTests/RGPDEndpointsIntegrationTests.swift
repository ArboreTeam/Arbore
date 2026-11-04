//
//  RGPDEndpointsIntegrationTests.swift
//  ArboreUiTests
//
//  Integration tests for RGPD endpoints (Data Export & Account Deletion)
//

import XCTest
import Firebase
import FirebaseAuth
@testable import ArboreUi

class RGPDEndpointsIntegrationTests: XCTestCase {

    var testUserUID: String?

    /// Chaque test ouvre lui-même la session dont il a besoin — invitée ou
    /// membre —, parce que cette suite couvre les DEUX parcours et qu'ils
    /// n'ont pas les mêmes droits. Le `setUp` ne fait donc que les contrôles
    /// communs.
    override func setUp() async throws {
        try LiveIntegrationTestGate.requireEnabled()
        try LiveIntegrationTestGate.requireBackendReachable(suite: "RGPD")
        if FirebaseApp.app() == nil { FirebaseApp.configure() }
    }

    /// Le compte du test — invité ou membre jetable — part avec ses données.
    /// Sans effet quand le test l'a déjà supprimé lui-même, ce qui est
    /// précisément ce que `testAccountDeletion_SessionInvitee` fait.
    override func tearDown() async throws {
        await LiveIntegrationTestGate.fermerEtDetruireLaSessionDeTest()
        testUserUID = nil
    }

    // MARK: - Helper Methods



    private func getFirebaseToken() async throws -> String {
        guard let user = Auth.auth().currentUser else {
            throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No authenticated user"])
        }

        let expectation = self.expectation(description: "Get Firebase token")
        var token: String?
        var tokenError: Error?

        user.getIDToken { idToken, error in
            if let error = error {
                tokenError = error
            } else {
                token = idToken
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)

        if let error = tokenError {
            throw error
        }

        guard let idToken = token else {
            throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get token"])
        }

        return idToken
    }

    /// Une erreur d'appel doit DIRE ce que le backend a répondu.
    ///
    /// Les messages précédents — « Failed to create garden » — ne
    /// distinguaient pas un 401 d'un 403 ni d'un 500. Quand ces suites ont
    /// enfin tourné, le 2026-11-03, il a fallu aller lire les journaux du
    /// serveur pour savoir pourquoi dix tests échouaient. Le statut et le
    /// corps suffisaient. (#725)
    static func echecHTTP(_ appel: String, response: URLResponse?, data: Data) -> NSError {
        let statut = (response as? HTTPURLResponse)?.statusCode
        let corps = String(data: data, encoding: .utf8) ?? "<corps illisible>"
        return NSError(
            domain: "TestError", code: statut ?? -1,
            userInfo: [NSLocalizedDescriptionKey:
                "\(appel) a rendu \(statut.map(String.init) ?? "aucun statut") — \(corps)"])
    }


    private func createTestGarden(uid: String, token: String) async throws -> String {
        let endpoint = "\(AppConfig.baseURL)/gardens"
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let gardenData: [String: Any] = [
            "uid": uid,
            "name": "Test Garden",
            "wizard": [
                "style": "modern",
                "spaceType": "indoor"
            ],
            "plants": []
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: gardenData)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw Self.echecHTTP("POST /gardens", response: response, data: data)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let gardenId = json?["id"] as? String else {
            throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No garden ID returned"])
        }

        return gardenId
    }

    private func createTestConsent(uid: String, token: String) async throws {
        let endpoint = "\(AppConfig.baseURL)/consents"
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let consentData: [String: Any] = [
            "consentType": "privacy_profilePublic",
            "version": "1.0.0",
            "granted": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: consentData)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            throw Self.echecHTTP("POST /consents", response: response, data: data)
        }
    }

    // MARK: - Data Export Tests

    /// Un INVITÉ exporte ses jardins — Art. 15, et c'est le parcours que
    /// #393 a rendu possible.
    ///
    /// Une session invitée n'a pas de document `users` : elle ne peut pas en
    /// créer un (`POST /users` est fermé aux invités) ni écrire de
    /// consentement. Elle détient néanmoins des jardins, et le droit d'accès
    /// porte dessus. Répondre 404 au motif qu'il n'y a pas de profil
    /// priverait son titulaire de données qui existent bel et bien — c'est
    /// exactement ce que le handler commente et que ce test verrouille.
    ///
    /// L'ancienne version créait un compte email/mot de passe jamais vérifié
    /// et échouait en `EMAIL_NOT_VERIFIED` dès `POST /gardens` (#725).
    func testDataExport_SessionInvitee_ExporteSesJardinsSansProfil() async throws {
        let invite = try await LiveIntegrationTestGate.ouvrirSessionInvitee()
        let token = try await getFirebaseToken()

        _ = try await createTestGarden(uid: invite.uid, token: token)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let (data, response) = try await appelerExport(token: token)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["exportDate"])
        XCTAssertNotNil(json?["gardens"])
        XCTAssertNotNil(json?["consents"])

        let gardens = json?["gardens"] as? [[String: Any]]
        XCTAssertGreaterThan(gardens?.count ?? 0, 0,
                             "l'invité détient un jardin, l'export doit le rendre")

        let metadata = json?["metadata"] as? [String: Any]
        XCTAssertEqual(metadata?["hasProfile"] as? Bool, false,
                       "l'absence de profil doit être DITE, pas masquée")
        XCTAssertEqual(metadata?["format"] as? String, "JSON")
        XCTAssertEqual(metadata?["version"] as? String, "1.0")

        let userData = json?["user"] as? [String: Any]
        XCTAssertEqual(userData?["uid"] as? String, invite.uid,
                       "l'uid reste rendu même sans document utilisateur")
    }

    /// Un MEMBRE exporte son profil et ses consentements.
    ///
    /// Complément du test précédent : il couvre ce qu'un invité ne peut pas
    /// avoir. Se saute proprement tant que le compte de test n'est pas
    /// provisionné.
    func testDataExport_SessionMembre_ExporteProfilEtConsentements() async throws {
        let membre = try await LiveIntegrationTestGate.ouvrirSessionMembre()
        let token = try await getFirebaseToken()

        // Créer le document `users`, comme l'app le fait à CHAQUE connexion.
        //
        // Une identité Firebase fraîche n'en a pas : `hasProfile` vaut alors
        // false et l'export ne porte que l'uid — ce qui est la bonne réponse
        // du backend, et ce que le test invité vérifie par ailleurs. Sans
        // cette étape, ce test-ci demanderait au backend un profil que
        // personne n'a créé.
        try await creerLeProfilBackend(membre: membre, token: token)
        try await createTestConsent(uid: membre.uid, token: token)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let (data, response) = try await appelerExport(token: token)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let metadata = json?["metadata"] as? [String: Any]
        XCTAssertEqual(metadata?["hasProfile"] as? Bool, true)

        let userData = json?["user"] as? [String: Any]
        XCTAssertEqual(userData?["uid"] as? String, membre.uid)
        XCTAssertEqual(userData?["email"] as? String, membre.email)

        let consents = json?["consents"] as? [[String: Any]]
        XCTAssertGreaterThan(consents?.count ?? 0, 0)

        // Le secret d'authentification Apple n'est PAS une donnée portable.
        let corps = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(corps.lowercased().contains("applerefreshtoken"),
                       "l'export ne doit jamais contenir le jeton Apple")
    }

    /// Upsert du document utilisateur, le même geste que l'app à la connexion.
    private func creerLeProfilBackend(membre: FirebaseAuth.User, token: String) async throws {
        guard let url = URL(string: "\(AppConfig.baseURL)/users") else {
            throw NSError(domain: "TestError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "URL /users invalide"])
        }
        var requete = URLRequest(url: url)
        requete.httpMethod = "POST"
        requete.setValue("application/json", forHTTPHeaderField: "Content-Type")
        requete.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        requete.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        requete.httpBody = try JSONSerialization.data(withJSONObject: [
            "uid": membre.uid,
            "email": membre.email ?? "",
            "name": "Compte de test",
            "createdAt": ISO8601DateFormatter().string(from: Date()),
        ])

        let (data, reponse) = try await URLSession.shared.data(for: requete)
        guard (reponse as? HTTPURLResponse)?.statusCode == 200 else {
            throw Self.echecHTTP("POST /users", response: reponse, data: data)
        }
    }

    private func appelerExport(token: String) async throws -> (Data, URLResponse) {
        guard let url = URL(string: "\(AppConfig.baseURL)/users/export") else {
            throw NSError(domain: "TestError", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "URL d'export invalide"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        return try await URLSession.shared.data(for: request)
    }

    func testDataExport_WithoutAuthentication_ShouldReturn401() async throws {
        // Arrange
        let endpoint = "\(AppConfig.baseURL)/users/export"
        guard let url = URL(string: endpoint) else {
            XCTFail("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        // No Authorization header

        // Act
        let (_, response) = try await URLSession.shared.data(for: request)

        // Assert
        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Invalid response type")
            return
        }

        XCTAssertEqual(httpResponse.statusCode, 401, "Should return 401 Unauthorized")
    }

    // MARK: - Account Deletion Tests

    /// Un INVITÉ supprime son compte et ses données — Art. 17.
    ///
    /// Ce test ne peut PAS utiliser le compte de test partagé : il détruit
    /// l'identité. Il lui faut donc une identité jetable, donc non
    /// vérifiable, donc invitée. Le découpage invité/membre de cette suite
    /// n'est pas une commodité, il est forcé par là.
    ///
    /// Et c'est le parcours que #393 a voulu : les routes d'export et de
    /// suppression sont sorties de `RequireAccount` parce qu'un invité ne
    /// peut exercer ses droits que depuis sa session courante — il n'a
    /// aucune identité à prouver ensuite.
    func testAccountDeletion_SessionInvitee_SupprimeSesDonnees() async throws {
        let invite = try await LiveIntegrationTestGate.ouvrirSessionInvitee()
        let token = try await getFirebaseToken()

        _ = try await createTestGarden(uid: invite.uid, token: token)
        try await Task.sleep(nanoseconds: 1_000_000_000)

        // Les données existent avant la suppression. Sans ce contrôle, un
        // « 0 jardin supprimé » passerait pour un succès.
        let (avant, _) = try await appelerExport(token: token)
        let jsonAvant = try JSONSerialization.jsonObject(with: avant) as? [String: Any]
        let jardinsAvant = jsonAvant?["gardens"] as? [[String: Any]]
        XCTAssertGreaterThan(jardinsAvant?.count ?? 0, 0,
                             "rien à supprimer : le test ne prouverait rien")

        guard let url = URL(string: "\(AppConfig.baseURL)/users") else {
            XCTFail("URL invalide"); return
        }
        var requete = URLRequest(url: url)
        requete.httpMethod = "DELETE"
        requete.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        requete.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        let (data, reponse) = try await URLSession.shared.data(for: requete)
        guard let http = reponse as? HTTPURLResponse else {
            XCTFail("réponse illisible"); return
        }
        XCTAssertEqual(http.statusCode, 200,
                       "corps : \(String(data: data, encoding: .utf8) ?? "")")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json?["message"])
        XCTAssertGreaterThan(json?["gardensDeleted"] as? Int ?? 0, 0,
                             "le jardin de l'invité doit être compté comme supprimé")
        XCTAssertEqual(json?["authenticationDeleted"] as? Bool, true,
                       "l'identité Firebase doit partir avec les données")

        // Et il ne reste rien : le jeton est encore valide quelques minutes,
        // donc l'export doit répondre un export VIDE, pas une erreur.
        let (apres, _) = try await appelerExport(token: token)
        let jsonApres = try JSONSerialization.jsonObject(with: apres) as? [String: Any]
        let jardinsApres = jsonApres?["gardens"] as? [[String: Any]]
        XCTAssertEqual(jardinsApres?.count ?? 0, 0,
                       "l'effacement doit être effectif, pas seulement annoncé")
    }

    func testAccountDeletion_WithoutAuthentication_ShouldReturn401() async throws {
        // Arrange
        let endpoint = "\(AppConfig.baseURL)/users"
        guard let url = URL(string: endpoint) else {
            XCTFail("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        // No Authorization header

        // Act
        let (_, response) = try await URLSession.shared.data(for: request)

        // Assert
        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Invalid response type")
            return
        }

        XCTAssertEqual(httpResponse.statusCode, 401, "Should return 401 Unauthorized")
    }
}
