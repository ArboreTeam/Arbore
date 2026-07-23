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

    var testUserEmail: String!
    var testUserPassword: String!
    var testUserUID: String?

    override func setUpWithError() throws {
        try super.setUpWithError()

        try LiveIntegrationTestGate.requireEnabled()
        try ensureBackendIsReachableOrSkip()

        // Configure Firebase
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }

        // Create unique test user credentials
        testUserEmail = "test.rgpd.\(UUID().uuidString.lowercased())@arbore.test"
        testUserPassword = "TestPassword123!"
    }

    private func ensureBackendIsReachableOrSkip() throws {
        guard let url = URL(string: "\(AppConfig.baseURL)/health") else {
            throw XCTSkip("RGPD integration tests skipped: invalid backend URL \(AppConfig.baseURL)")
        }

        let expectation = self.expectation(description: "Backend health check")
        var isReachable = false

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                isReachable = true
            }
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: 7.0)

        if !isReachable {
            throw XCTSkip("RGPD integration tests skipped: backend is unreachable at \(AppConfig.baseURL)")
        }
    }

    override func tearDownWithError() throws {
        // Cleanup: delete test user if created
        if let currentUser = Auth.auth().currentUser {
            let expectation = self.expectation(description: "Delete test user")
            currentUser.delete { error in
                if let error = error {
                    print("⚠️ Failed to delete test user: \(error)")
                }
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 10.0)
        }

        try super.tearDownWithError()
    }

    // MARK: - Helper Methods

    private func createTestUser() async throws -> FirebaseAuth.User {
        let expectation = self.expectation(description: "Create test user")
        var createdUser: FirebaseAuth.User?
        var authError: Error?

        Auth.auth().createUser(withEmail: testUserEmail, password: testUserPassword) { result, error in
            if let error = error {
                authError = error
            } else {
                createdUser = result?.user
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)

        if let error = authError {
            throw error
        }

        guard let user = createdUser else {
            throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create user"])
        }

        testUserUID = user.uid
        return user
    }

    private func signInTestUser() async throws -> FirebaseAuth.User {
        let expectation = self.expectation(description: "Sign in test user")
        var signedInUser: FirebaseAuth.User?
        var authError: Error?

        Auth.auth().signIn(withEmail: testUserEmail, password: testUserPassword) { result, error in
            if let error = error {
                authError = error
            } else {
                signedInUser = result?.user
            }
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 10.0)

        if let error = authError {
            throw error
        }

        guard let user = signedInUser else {
            throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to sign in"])
        }

        testUserUID = user.uid
        return user
    }

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

    private func createUserInBackend(uid: String, email: String, name: String, token: String) async throws {
        let endpoint = "\(AppConfig.baseURL)/users"
        guard let url = URL(string: endpoint) else {
            throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let userData: [String: Any] = [
            "uid": uid,
            "email": email,
            "name": name,
            "createdAt": ISO8601DateFormatter().string(from: Date())
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: userData)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create user in backend"])
        }
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
            throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create garden"])
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

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 201 else {
            throw NSError(domain: "TestError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to create consent"])
        }
    }

    // MARK: - Data Export Tests

    func testDataExport_WithValidUser_ShouldReturnCompleteData() async throws {
        // Arrange
        let user = try await createTestUser()
        let token = try await getFirebaseToken()

        // Create user in backend
        try await createUserInBackend(uid: user.uid, email: user.email ?? "", name: "Test User", token: token)

        // Create test data
        _ = try await createTestGarden(uid: user.uid, token: token)
        try await createTestConsent(uid: user.uid, token: token)

        // Wait a bit for data to be saved
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Act
        let endpoint = "\(AppConfig.baseURL)/users/export"
        guard let url = URL(string: endpoint) else {
            XCTFail("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        let (data, response) = try await URLSession.shared.data(for: request)

        // Assert
        guard let httpResponse = response as? HTTPURLResponse else {
            XCTFail("Invalid response type")
            return
        }

        XCTAssertEqual(httpResponse.statusCode, 200, "Should return 200 OK")

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(json, "Should return valid JSON")

        // Verify export structure
        XCTAssertNotNil(json?["exportDate"], "Should include exportDate")
        XCTAssertNotNil(json?["user"], "Should include user data")
        XCTAssertNotNil(json?["gardens"], "Should include gardens")
        XCTAssertNotNil(json?["consents"], "Should include consents")
        XCTAssertNotNil(json?["metadata"], "Should include metadata")

        // Verify user data
        let userData = json?["user"] as? [String: Any]
        XCTAssertEqual(userData?["uid"] as? String, user.uid, "Should include correct UID")
        XCTAssertEqual(userData?["email"] as? String, user.email, "Should include correct email")

        // Verify gardens array
        let gardens = json?["gardens"] as? [[String: Any]]
        XCTAssertNotNil(gardens, "Gardens should be an array")
        XCTAssertGreaterThan(gardens?.count ?? 0, 0, "Should have at least 1 garden")

        // Verify consents array
        let consents = json?["consents"] as? [[String: Any]]
        XCTAssertNotNil(consents, "Consents should be an array")
        XCTAssertGreaterThan(consents?.count ?? 0, 0, "Should have at least 1 consent")

        // Verify metadata
        let metadata = json?["metadata"] as? [String: Any]
        XCTAssertEqual(metadata?["format"] as? String, "JSON", "Format should be JSON")
        XCTAssertEqual(metadata?["version"] as? String, "1.0", "Version should be 1.0")
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

    func testAccountDeletion_WithValidUser_ShouldDeleteAllData() async throws {
        // Arrange
        let user = try await createTestUser()
        let token = try await getFirebaseToken()

        // Create user in backend
        try await createUserInBackend(uid: user.uid, email: user.email ?? "", name: "Test User", token: token)

        // Create test data
        let gardenId = try await createTestGarden(uid: user.uid, token: token)
        try await createTestConsent(uid: user.uid, token: token)

        // Wait a bit for data to be saved
        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

        // Verify data exists before deletion
        let exportBeforeEndpoint = "\(AppConfig.baseURL)/users/export"
        guard let exportBeforeURL = URL(string: exportBeforeEndpoint) else {
            XCTFail("Invalid URL")
            return
        }

        var exportBeforeRequest = URLRequest(url: exportBeforeURL)
        exportBeforeRequest.httpMethod = "GET"
        exportBeforeRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        exportBeforeRequest.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        let (dataBefore, _) = try await URLSession.shared.data(for: exportBeforeRequest)
        let jsonBefore = try JSONSerialization.jsonObject(with: dataBefore) as? [String: Any]

        let gardensBefore = jsonBefore?["gardens"] as? [[String: Any]]
        let consentsBefore = jsonBefore?["consents"] as? [[String: Any]]

        XCTAssertGreaterThan(gardensBefore?.count ?? 0, 0, "Should have gardens before deletion")
        XCTAssertGreaterThan(consentsBefore?.count ?? 0, 0, "Should have consents before deletion")

        // Act - Delete account
        let deleteEndpoint = "\(AppConfig.baseURL)/users"
        guard let deleteURL = URL(string: deleteEndpoint) else {
            XCTFail("Invalid URL")
            return
        }

        var deleteRequest = URLRequest(url: deleteURL)
        deleteRequest.httpMethod = "DELETE"
        deleteRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        deleteRequest.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        let (deleteData, deleteResponse) = try await URLSession.shared.data(for: deleteRequest)

        // Assert deletion response
        guard let deleteHttpResponse = deleteResponse as? HTTPURLResponse else {
            XCTFail("Invalid response type")
            return
        }

        XCTAssertEqual(deleteHttpResponse.statusCode, 200, "Should return 200 OK")

        let deleteJson = try JSONSerialization.jsonObject(with: deleteData) as? [String: Any]
        XCTAssertNotNil(deleteJson?["message"], "Should include success message")
        XCTAssertNotNil(deleteJson?["gardensDeleted"], "Should report gardens deleted count")
        XCTAssertNotNil(deleteJson?["consentsDeleted"], "Should report consents deleted count")

        // Verify counts
        let gardensDeleted = deleteJson?["gardensDeleted"] as? Int
        let consentsDeleted = deleteJson?["consentsDeleted"] as? Int

        XCTAssertGreaterThan(gardensDeleted ?? 0, 0, "Should have deleted at least 1 garden")
        XCTAssertGreaterThan(consentsDeleted ?? 0, 0, "Should have deleted at least 1 consent")
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
