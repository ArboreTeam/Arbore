//
//  FirebaseConfigDiagnosticTests.swift
//  ArboreUiTests
//
//  Created by CI Diagnostic Tests
//  Tests to diagnose Firebase and configuration issues in CI
//

import XCTest
import Firebase
import FirebaseAuth
@testable import ArboreUi

class FirebaseConfigDiagnosticTests: XCTestCase {

    private func isBackendReachable(timeout: TimeInterval = 5.0) -> Bool {
        guard let url = URL(string: "\(AppConfig.baseURL)/health") else {
            return false
        }

        let expectation = XCTestExpectation(description: "Backend health check")
        var isReachable = false

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout

        URLSession.shared.dataTask(with: request) { _, response, _ in
            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                isReachable = true
            }
            expectation.fulfill()
        }.resume()

        wait(for: [expectation], timeout: timeout + 2.0)
        return isReachable
    }
    
    /// Test 1: Verify AppConfig secrets are properly loaded
    func testDiagnostic_AppConfig_SecretsLoaded() {
        NSLog("\n========================================")
        NSLog("🔍 DIAGNOSTIC: Testing AppConfig Secrets")
        NSLog("========================================")
        
        // Check API Key
        NSLog("📝 API Key: \(AppConfig.apiKey.prefix(10))... (length: \(AppConfig.apiKey.count))")
        XCTAssertFalse(AppConfig.apiKey.isEmpty, "API Key should not be empty")
        XCTAssertFalse(AppConfig.apiKey.contains("$("), "API Key should not contain placeholder")
        XCTAssertGreaterThan(AppConfig.apiKey.count, 10, "API Key seems too short")
        
        // Check Base URL
        NSLog("📝 Base URL: \(AppConfig.baseURL)")
        XCTAssertFalse(AppConfig.baseURL.isEmpty, "Base URL should not be empty")
        XCTAssertTrue(AppConfig.baseURL.hasPrefix("http://") || AppConfig.baseURL.hasPrefix("https://"),
                     "Base URL should start with http:// or https://")
        
        NSLog("✅ AppConfig secrets are properly loaded")
        NSLog("========================================\n")
    }
    
    /// Test 2: Verify Firebase is configured properly
    func testDiagnostic_Firebase_Configuration() {
        NSLog("\n========================================")
        NSLog("🔍 DIAGNOSTIC: Testing Firebase Config")
        NSLog("========================================")
        
        // Configure Firebase if needed
        if FirebaseApp.app() == nil {
            NSLog("📝 Configuring Firebase for the first time...")
            FirebaseApp.configure()
        } else {
            NSLog("📝 Firebase already configured")
        }
        
        // Verify Firebase app exists
        XCTAssertNotNil(FirebaseApp.app(), "Firebase app should be configured")
        
        // Check Firebase options
        if let firebaseApp = FirebaseApp.app() {
            NSLog("📝 Firebase App Name: \(firebaseApp.name)")
            let options = firebaseApp.options
            // Handle both String and String? for apiKey across Firebase versions
            let apiKeyStr = "\(options.apiKey)"
            let googleAppIDStr = "\(options.googleAppID)"
            let clientIDStr = options.clientID.map { "\($0)" } ?? "nil"
            let projectIDStr = options.projectID ?? "nil"
            
            NSLog("📝 Firebase API Key: \(apiKeyStr.prefix(10))...")
            NSLog("📝 Firebase Project ID: \(projectIDStr)")
            NSLog("📝 Firebase App ID: \(googleAppIDStr.prefix(20))...")
            NSLog("📝 Firebase Client ID: \(clientIDStr.prefix(20))...")
            
            // In CI, these should all be properly configured
            // In local dev, they might be placeholder values
            if apiKeyStr.contains("nil") || apiKeyStr.contains("Optional") {
                NSLog("⚠️ Firebase API Key appears to be nil or Optional - this is expected in local dev without GoogleService-Info.plist")
            } else {
                XCTAssertFalse(apiKeyStr.isEmpty, "Firebase API Key should exist in CI")
            }
            
            XCTAssertFalse(googleAppIDStr.isEmpty, "Firebase App ID should not be empty")
        }
        
        // Check Auth instance
        let auth = Auth.auth()
        NSLog("📝 Auth currentUser: \(auth.currentUser?.uid ?? "nil")")
        NSLog("📝 Auth app: \(auth.app?.name ?? "nil")")
        
        NSLog("✅ Firebase configuration verified")
        NSLog("========================================\n")
    }
    
    /// Test 3: Test Firebase network connectivity
    func testDiagnostic_Firebase_NetworkConnectivity() throws {
        try LiveIntegrationTestGate.requireEnabled()

        XCTContext.runActivity(named: "🔍 DIAGNOSTIC: Testing Firebase Network") { _ in
            // Configure Firebase if needed
            if FirebaseApp.app() == nil {
                FirebaseApp.configure()
            }
            
            let expectation = XCTestExpectation(description: "Test Firebase connectivity")
            let startTime = Date()
            
            let testEmail = "diagnostic-test-\(UUID().uuidString.lowercased())@arbore.test"
            let testPassword = "DiagnosticTest2026!"
            
            Auth.auth().createUser(withEmail: testEmail, password: testPassword) { result, error in
                let elapsed = Date().timeIntervalSince(startTime)
                
                if let error = error {
                    let nsError = error as NSError
                    // Use XCTFail which appears in logs
                    let errorMsg = """
                    ❌ Firebase createUser FAILED after \(String(format: "%.2f", elapsed))s
                    📝 Error domain: \(nsError.domain)
                    📝 Error code: \(nsError.code)
                    📝 Description: \(error.localizedDescription)
                    📝 UserInfo: \(nsError.userInfo)
                    """
                    XCTFail(errorMsg)
                } else {
                    // Clean up: delete the test user
                    result?.user.delete { deleteError in
                        if let deleteError = deleteError {
                            XCTFail("⚠️ Failed to delete diagnostic user: \(deleteError.localizedDescription)")
                        }
                        expectation.fulfill()
                    }
                    return
                }
                
                expectation.fulfill()
            }
            
            wait(for: [expectation], timeout: 30.0)
        }
    }
    
    /// Test 4: Verify backend connectivity
    func testDiagnostic_Backend_Connectivity() throws {
        try LiveIntegrationTestGate.requireEnabled()

        NSLog("\n========================================")
        NSLog("🔍 DIAGNOSTIC: Testing Backend Connection")
        NSLog("========================================")
        
        NSLog("📝 Backend URL: \(AppConfig.baseURL)")

        if !isBackendReachable(timeout: 5.0) {
            throw XCTSkip("Backend diagnostic skipped: backend is unreachable at \(AppConfig.baseURL)")
        }
        
        let expectation = XCTestExpectation(description: "Backend health check")
        let startTime = Date()
        
        guard let url = URL(string: "\(AppConfig.baseURL)/health") else {
            XCTFail("Invalid backend URL")
            return
        }
        
        NSLog("📝 Attempting to connect to: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 10.0
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            let elapsed = Date().timeIntervalSince(startTime)
            
            if let error = error {
                NSLog("❌ Backend connection failed after \(String(format: "%.2f", elapsed))s")
                NSLog("📝 Error: \(error.localizedDescription)")
                XCTFail("Backend not reachable: \(error.localizedDescription)")
            } else if let httpResponse = response as? HTTPURLResponse {
                NSLog("✅ Backend responded in \(String(format: "%.2f", elapsed))s")
                NSLog("📝 Status code: \(httpResponse.statusCode)")
                
                if let data = data, let body = String(data: data, encoding: .utf8) {
                    NSLog("📝 Response body: \(body)")
                }
                
                XCTAssertEqual(httpResponse.statusCode, 200, "Backend health check should return 200")
            }
            
            expectation.fulfill()
        }.resume()
        
        wait(for: [expectation], timeout: 15.0)
        NSLog("========================================\n")
    }
}
