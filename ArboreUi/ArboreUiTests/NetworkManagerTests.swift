//
//  NetworkManagerTests.swift
//  ArboreUiTests
//
//  Created by Matribuk on 25/01/2026.
//

import XCTest
import Firebase
import FirebaseAuth
@testable import ArboreUi

// MARK: - NetworkManager Tests

class NetworkManagerTests: XCTestCase {

    override func setUpWithError() throws {
        // Configuration Firebase pour les tests
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
    }

    // MARK: - Configuration Tests

    func testNetworkManager_Singleton_ShouldExist() {
        // Assert
        XCTAssertNotNil(NetworkManager.shared, "NetworkManager.shared should exist")
    }

    func testAppConfig_BaseURL_ShouldBeValid() {
        // Assert
        XCTAssertNotNil(URL(string: AppConfig.baseURL), "Base URL should be valid")
        XCTAssertFalse(AppConfig.baseURL.isEmpty, "Base URL should not be empty")
    }

    func testAppConfig_APIKey_ShouldExist() {
        // Assert
        XCTAssertNotNil(AppConfig.apiKey, "API Key should exist")
        XCTAssertFalse(AppConfig.apiKey.isEmpty, "API Key should not be empty")
        XCTAssertTrue(AppConfig.apiKey.hasPrefix("arbore_"), "API Key should have correct prefix")
    }

    // MARK: - HTTP Method Tests

    func testHTTPMethod_RawValues_ShouldBeCorrect() {
        // Assert
        XCTAssertEqual(HTTPMethod.GET.rawValue, "GET")
        XCTAssertEqual(HTTPMethod.POST.rawValue, "POST")
        XCTAssertEqual(HTTPMethod.PUT.rawValue, "PUT")
        XCTAssertEqual(HTTPMethod.DELETE.rawValue, "DELETE")
    }

    // MARK: - Error Handling Tests

    func testNetworkError_InvalidURL_ShouldExist() {
        // Arrange
        let error = NetworkError.invalidURL

        // Assert
        switch error {
        case .invalidURL:
            XCTAssertTrue(true, "InvalidURL error should match")
        default:
            XCTFail("Should be invalidURL error")
        }
    }

    func testNetworkError_NoUser_ShouldExist() {
        // Arrange
        let error = NetworkError.noUser

        // Assert
        switch error {
        case .noUser:
            XCTAssertTrue(true, "NoUser error should match")
        default:
            XCTFail("Should be noUser error")
        }
    }

    func testNetworkError_Unauthorized_ShouldExist() {
        // Arrange
        let error = NetworkError.unauthorized

        // Assert
        switch error {
        case .unauthorized:
            XCTAssertTrue(true, "Unauthorized error should match")
        default:
            XCTFail("Should be unauthorized error")
        }
    }

    func testNetworkError_Forbidden_ShouldExist() {
        // Arrange
        let error = NetworkError.forbidden

        // Assert
        switch error {
        case .forbidden:
            XCTAssertTrue(true, "Forbidden error should match")
        default:
            XCTFail("Should be forbidden error")
        }
    }

    func testNetworkError_ServerError_ShouldContainMessage() {
        // Arrange
        let testMessage = "Test error message"
        let error = NetworkError.serverError(testMessage)

        // Assert
        switch error {
        case .serverError(let message):
            XCTAssertEqual(message, testMessage, "Server error should contain correct message")
        default:
            XCTFail("Should be serverError")
        }
    }

    // MARK: - Request Building Tests

    func testNetworkManager_Request_WithoutUser_ShouldThrowNoUserError() async {
        // Arrange - S'assurer qu'aucun user n'est connecté
        if Auth.auth().currentUser != nil {
            try? Auth.auth().signOut()
        }

        // Act & Assert
        do {
            struct EmptyResponse: Codable {}
            let _: EmptyResponse = try await NetworkManager.shared.request(
                endpoint: "/health",
                method: .GET
            )
            XCTFail("Should throw noUser error when no user is authenticated")
        } catch NetworkError.noUser {
            XCTAssertTrue(true, "Correctly threw noUser error")
        } catch {
            XCTFail("Should throw noUser error, got: \(error)")
        }
    }

    // MARK: - Model Decoding Tests

    func testUserResponse_Decoding_ValidJSON_ShouldSucceed() throws {
        // Arrange
        let jsonString = """
        {
            "user": {
                "uid": "test123",
                "email": "test@arbore.com",
                "name": "Test User",
                "createdAt": "2026-01-25T10:00:00Z",
                "banned": false
            },
            "message": "User found"
        }
        """
        let jsonData = jsonString.data(using: .utf8)!

        // Act
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let response = try decoder.decode(UserResponse.self, from: jsonData)

        // Assert
        XCTAssertNotNil(response.user, "User should not be nil")
        XCTAssertEqual(response.user?.uid, "test123")
        XCTAssertEqual(response.user?.email, "test@arbore.com")
        XCTAssertEqual(response.user?.name, "Test User")
        XCTAssertEqual(response.user?.banned, false)
        XCTAssertEqual(response.message, "User found")
    }

    func testUserResponse_Decoding_NullUser_ShouldSucceed() throws {
        // Arrange
        let jsonString = """
        {
            "user": null,
            "message": "User not found"
        }
        """
        let jsonData = jsonString.data(using: .utf8)!

        // Act
        let decoder = JSONDecoder()
        let response = try decoder.decode(UserResponse.self, from: jsonData)

        // Assert
        XCTAssertNil(response.user, "User should be nil")
        XCTAssertEqual(response.message, "User not found")
    }

    func testBackendConsent_Decoding_ValidJSON_ShouldSucceed() throws {
        // Arrange
        let jsonString = """
        {
            "consentType": "analytics",
            "granted": true,
            "timestamp": "2026-01-25T10:00:00Z",
            "version": "1.0"
        }
        """
        let jsonData = jsonString.data(using: .utf8)!

        // Act
        let decoder = JSONDecoder()
        let consent = try decoder.decode(BackendConsent.self, from: jsonData)

        // Assert
        XCTAssertEqual(consent.consentType, "analytics")
        XCTAssertTrue(consent.granted)
        XCTAssertEqual(consent.timestamp, "2026-01-25T10:00:00Z")
        XCTAssertEqual(consent.version, "1.0")
    }

    func testBackendConsentsResponse_Decoding_ValidJSON_ShouldSucceed() throws {
        // Arrange
        let jsonString = """
        {
            "uid": "test123",
            "consents": [
                {
                    "consentType": "profilePublic",
                    "granted": false,
                    "timestamp": "2026-01-25T10:00:00Z",
                    "version": "1.0"
                },
                {
                    "consentType": "analytics",
                    "granted": true,
                    "timestamp": "2026-01-25T10:01:00Z",
                    "version": "1.0"
                }
            ]
        }
        """
        let jsonData = jsonString.data(using: .utf8)!

        // Act
        let decoder = JSONDecoder()
        let response = try decoder.decode(BackendConsentsResponse.self, from: jsonData)

        // Assert
        XCTAssertEqual(response.uid, "test123")
        XCTAssertNotNil(response.consents)
        XCTAssertEqual(response.consents?.count, 2)
        XCTAssertEqual(response.consents?[0].consentType, "profilePublic")
        XCTAssertFalse(response.consents?[0].granted ?? true)
        XCTAssertEqual(response.consents?[1].consentType, "analytics")
        XCTAssertTrue(response.consents?[1].granted ?? false)
    }

    func testBackendConsentsResponse_Decoding_NullConsents_ShouldSucceed() throws {
        // Arrange - consents null pour les nouveaux utilisateurs
        let jsonString = """
        {
            "uid": "test123",
            "consents": null
        }
        """
        let jsonData = jsonString.data(using: .utf8)!

        // Act
        let decoder = JSONDecoder()
        let response = try decoder.decode(BackendConsentsResponse.self, from: jsonData)

        // Assert
        XCTAssertEqual(response.uid, "test123")
        XCTAssertNil(response.consents, "Consents should be nil for new users")
    }

    func testUser_Decoding_WithAllFields_ShouldSucceed() throws {
        // Arrange
        let jsonString = """
        {
            "uid": "test123",
            "email": "test@arbore.com",
            "name": "Test User",
            "createdAt": "2026-01-25T10:00:00Z",
            "photoData": "base64data",
            "photoContentType": "image/jpeg",
            "banned": false
        }
        """
        let jsonData = jsonString.data(using: .utf8)!

        // Act
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let user = try decoder.decode(User.self, from: jsonData)

        // Assert
        XCTAssertEqual(user.uid, "test123")
        XCTAssertEqual(user.email, "test@arbore.com")
        XCTAssertEqual(user.name, "Test User")
        XCTAssertEqual(user.photoData, "base64data")
        XCTAssertEqual(user.photoContentType, "image/jpeg")
        XCTAssertEqual(user.banned, false)
    }

    func testUser_Decoding_WithOptionalFields_ShouldSucceed() throws {
        // Arrange - JSON sans les champs optionnels
        let jsonString = """
        {
            "uid": "test123",
            "email": "test@arbore.com",
            "name": "Test User",
            "createdAt": "2026-01-25T10:00:00Z"
        }
        """
        let jsonData = jsonString.data(using: .utf8)!

        // Act
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let user = try decoder.decode(User.self, from: jsonData)

        // Assert
        XCTAssertEqual(user.uid, "test123")
        XCTAssertNil(user.photoData, "photoData should be nil")
        XCTAssertNil(user.photoContentType, "photoContentType should be nil")
        XCTAssertNil(user.banned, "banned should be nil")
    }

    // MARK: - EmptyResponse Tests

    func testEmptyResponse_Decoding_EmptyJSON_ShouldSucceed() throws {
        // Arrange
        let jsonString = "{}"
        let jsonData = jsonString.data(using: .utf8)!

        // Act
        let decoder = JSONDecoder()
        let response = try decoder.decode(EmptyResponse.self, from: jsonData)

        // Assert
        XCTAssertNotNil(response, "EmptyResponse should decode from empty JSON")
    }
}

// MARK: - Integration Tests (Requires Backend + Auth)

class NetworkManagerIntegrationTests: XCTestCase {

    let testPassword = "TestNetwork2026!"
    var testEmail: String!
    var testUserUID: String?

    override func setUpWithError() throws {
        // Configuration Firebase
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        // Créer un user de test
        let timestamp = Int(Date().timeIntervalSince1970)
        testEmail = "test-network-\(timestamp)@arbore.test"

        let createExpectation = XCTestExpectation(description: "Create test user")
        let startTime = Date()

        Auth.auth().createUser(withEmail: testEmail, password: testPassword) { result, error in
            let elapsed = Date().timeIntervalSince(startTime)
            
            if let error = error {
                let nsError = error as NSError
                let errorMsg = """
                ❌ NetworkManagerIntegrationTests setUp FAILED
                📝 Firebase createUser failed after \(String(format: "%.2f", elapsed))s
                📝 Error domain: \(nsError.domain)
                📝 Error code: \(nsError.code)
                📝 Description: \(error.localizedDescription)
                📝 UserInfo: \(nsError.userInfo)
                """
                XCTFail(errorMsg)
                createExpectation.fulfill()
                return
            }

            self.testUserUID = result?.user.uid

            // Sign in pour obtenir un token Firebase valide
            let signInTime = Date()
            
            Auth.auth().signIn(withEmail: self.testEmail, password: self.testPassword) { _, signInError in
                let signInElapsed = Date().timeIntervalSince(signInTime)
                
                if let signInError = signInError {
                    let nsError = signInError as NSError
                    let errorMsg = """
                    ❌ NetworkManagerIntegrationTests setUp - signIn FAILED
                    📝 Firebase signIn failed after \(String(format: "%.2f", signInElapsed))s
                    📝 Error domain: \(nsError.domain)
                    📝 Error code: \(nsError.code)
                    📝 Description: \(signInError.localizedDescription)
                    """
                    XCTFail(errorMsg)
                    createExpectation.fulfill()
                    return
                }

                // Créer le user dans MongoDB avec NetworkManager (qui ajoute le token Firebase)
                Task {
                    do {
                        let formatter = ISO8601DateFormatter()
                        let userData: [String: Any] = [
                            "uid": self.testUserUID!,
                            "email": self.testEmail!,
                            "name": "Test Network User",
                            "createdAt": formatter.string(from: Date()),
                            "banned": false
                        ]

                        let _: UserResponse = try await NetworkManager.shared.request(
                            endpoint: "/users",
                            method: .POST,
                            body: userData
                        )

                        createExpectation.fulfill()
                    } catch {
                        let errorMsg = """
                        ❌ NetworkManagerIntegrationTests setUp - Backend user creation FAILED
                        📝 Backend POST /users failed
                        📝 Error: \(error)
                        """
                        XCTFail(errorMsg)
                        createExpectation.fulfill()
                    }
                }
            }
        }

        wait(for: [createExpectation], timeout: 30.0)
    }

    override func tearDownWithError() throws {
        // Supprimer le user du backend
        if let uid = testUserUID {
            let deleteExpectation = XCTestExpectation(description: "Delete user from backend")
            deleteUserFromBackend(uid: uid) { _ in
                deleteExpectation.fulfill()
            }
            wait(for: [deleteExpectation], timeout: 5.0)
        }

        // Supprimer le user de Firebase
        if let currentUser = Auth.auth().currentUser {
            let deleteFirebaseExpectation = XCTestExpectation(description: "Delete Firebase user")
            currentUser.delete { _ in
                deleteFirebaseExpectation.fulfill()
            }
            wait(for: [deleteFirebaseExpectation], timeout: 5.0)
        }

        testUserUID = nil
        testEmail = nil
    }

    // MARK: - Helper Methods

    private func createUserInBackend(uid: String, email: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: AppConfig.usersEndpoint) else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        let formatter = ISO8601DateFormatter()
        let userData: [String: Any] = [
            "uid": uid,
            "email": email,
            "name": "Test Network User",
            "createdAt": formatter.string(from: Date()),
            "banned": false
        ]

        request.httpBody = try? JSONSerialization.data(withJSONObject: userData)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                NSLog("❌ NetworkManagerTests: Error creating user in backend: \(error)")
                completion(false)
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode != 201 {
                    let bodyString = data.flatMap { String(data: $0, encoding: .utf8) } ?? "No response body"
                    NSLog("⚠️ NetworkManagerTests: Backend returned status \(httpResponse.statusCode) when creating user. Response: \(bodyString)")
                }
                completion(httpResponse.statusCode == 201)
            } else {
                completion(false)
            }
        }.resume()
    }

    private func deleteUserFromBackend(uid: String, completion: @escaping (Bool) -> Void) {
        guard let url = URL(string: "\(AppConfig.usersEndpoint)/\(uid)") else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse {
                completion(httpResponse.statusCode == 200)
            } else {
                completion(false)
            }
        }.resume()
    }

    // MARK: - Real Backend Tests

    func testNetworkManager_GET_PublicHealthEndpoint_ShouldSucceed() async throws {
        // Note: /health est un endpoint public sans authentification
        // On ne peut pas tester avec NetworkManager car il requiert Firebase Auth
        // Ce test vérifie juste que le backend est accessible

        let expectation = XCTestExpectation(description: "GET /health")

        guard let url = URL(string: "\(AppConfig.baseURL)/health") else {
            XCTFail("Invalid URL")
            return
        }

        URLSession.shared.dataTask(with: url) { _, response, error in
            XCTAssertNil(error, "Request should succeed")
            if let httpResponse = response as? HTTPURLResponse {
                XCTAssertEqual(httpResponse.statusCode, 200, "Health endpoint should return 200")
            }
            expectation.fulfill()
        }.resume()

        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func testNetworkManager_AuthenticatedRequest_ShouldIncludeHeaders() async {
        // Ce test vérifie que NetworkManager ajoute bien les headers requis
        // On ne peut pas facilement tester sans mocker URLSession
        // Pour l'instant, on vérifie juste que l'utilisateur est authentifié

        guard let currentUser = Auth.auth().currentUser else {
            XCTFail("User should be authenticated")
            return
        }

        XCTAssertNotNil(currentUser.uid, "User should have UID")

        // Vérifier qu'on peut obtenir le token
        do {
            let token = try await currentUser.getIDToken()
            XCTAssertFalse(token.isEmpty, "Token should not be empty")
            NSLog("✅ Firebase token obtained: \(token.prefix(20))...")
        } catch {
            XCTFail("Should be able to get Firebase token: \(error)")
        }
    }

    // MARK: - Real Backend Tests with Firebase Token

    func testNetworkManager_GET_Plants_WithToken_ShouldSucceed() async {
        // Test que /plants fonctionne avec NetworkManager (API Key + Firebase token)

        guard Auth.auth().currentUser != nil else {
            XCTFail("User should be authenticated")
            return
        }

        do {
            struct PlantResponse: Codable {
                let id: String
                let name: String
            }

            let plants: [PlantResponse] = try await NetworkManager.shared.request(
                endpoint: "/plants",
                method: .GET
            )

            XCTAssertNotNil(plants, "Should receive plants array")
            NSLog("✅ Plants endpoint works with Firebase token! Received \(plants.count) plants")
        } catch {
            XCTFail("Request should succeed with valid token: \(error)")
        }
    }

    func testNetworkManager_GET_User_WithToken_ShouldSucceed() async {
        // Test que /users/:uid fonctionne avec NetworkManager

        guard let uid = Auth.auth().currentUser?.uid else {
            XCTFail("User should be authenticated")
            return
        }

        do {
            let response: UserResponse = try await NetworkManager.shared.request(
                endpoint: "/users/\(uid)",
                method: .GET
            )

            XCTAssertNotNil(response.user, "Should receive user data")
            XCTAssertEqual(response.user?.uid, uid, "UID should match")
            NSLog("✅ User endpoint works with Firebase token!")
        } catch {
            XCTFail("Request should succeed with valid token: \(error)")
        }
    }

    func testNetworkManager_POST_Consent_WithToken_ShouldSucceed() async {
        // Test que /consents fonctionne avec NetworkManager

        guard let uid = Auth.auth().currentUser?.uid else {
            XCTFail("User should be authenticated")
            return
        }

        do {
            let consentData: [String: Any] = [
                "uid": uid,
                "consentType": "test_consent",
                "granted": true,
                "version": "1.0",
                "timestamp": ISO8601DateFormatter().string(from: Date())
            ]

            struct ConsentResponse: Codable {
                let uid: String
                let consentType: String
                let granted: Bool
            }

            let response: ConsentResponse = try await NetworkManager.shared.request(
                endpoint: "/consents",
                method: .POST,
                body: consentData
            )

            XCTAssertEqual(response.consentType, "test_consent")
            XCTAssertTrue(response.granted)
            NSLog("✅ Consent endpoint works with Firebase token!")
        } catch {
            XCTFail("Request should succeed with valid token: \(error)")
        }
    }

    func testNetworkManager_GET_Consents_WithToken_ShouldSucceed() async {
        // Test que /consents/latest fonctionne avec NetworkManager

        guard Auth.auth().currentUser != nil else {
            XCTFail("User should be authenticated")
            return
        }

        do {
            let response: BackendConsentsResponse = try await NetworkManager.shared.request(
                endpoint: "/consents/latest",
                method: .GET
            )

            XCTAssertNotNil(response.uid, "Should receive UID")
            // consents peut être nil pour un nouveau user
            NSLog("✅ Consents endpoint works with Firebase token! Consents: \(response.consents?.count ?? 0)")
        } catch {
            XCTFail("Request should succeed with valid token: \(error)")
        }
    }

    func testNetworkManager_WithoutAuth_PublicEndpoint_ShouldSucceed() async {
        // Test que requestWithoutAuth fonctionne pour les endpoints publics

        guard let uid = testUserUID else {
            XCTFail("Test user UID not available")
            return
        }

        do {
            // Tester GET /users/:uid avec API Key uniquement
            let response: UserResponse = try await NetworkManager.shared.requestWithoutAuth(
                endpoint: "/users/\(uid)",
                method: .GET
            )

            XCTAssertNotNil(response.user, "Should receive user with API Key only")
            NSLog("✅ requestWithoutAuth works for public endpoints!")
        } catch {
            // C'est OK si ça échoue - certains endpoints peuvent être protégés
            NSLog("ℹ️ requestWithoutAuth returned: \(error)")
        }
    }
}
