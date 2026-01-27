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
    
    /// Test 1: Verify AppConfig secrets are properly loaded
    func testDiagnostic_AppConfig_SecretsLoaded() {
        print("\n========================================")
        print("🔍 DIAGNOSTIC: Testing AppConfig Secrets")
        print("========================================")
        
        // Check API Key
        print("📝 API Key: \(AppConfig.apiKey.prefix(10))... (length: \(AppConfig.apiKey.count))")
        XCTAssertFalse(AppConfig.apiKey.isEmpty, "API Key should not be empty")
        XCTAssertFalse(AppConfig.apiKey.contains("$("), "API Key should not contain placeholder")
        XCTAssertGreaterThan(AppConfig.apiKey.count, 10, "API Key seems too short")
        
        // Check Base URL
        print("📝 Base URL: \(AppConfig.baseURL)")
        XCTAssertFalse(AppConfig.baseURL.isEmpty, "Base URL should not be empty")
        XCTAssertTrue(AppConfig.baseURL.hasPrefix("http://") || AppConfig.baseURL.hasPrefix("https://"),
                     "Base URL should start with http:// or https://")
        
        print("✅ AppConfig secrets are properly loaded")
        print("========================================\n")
    }
    
    /// Test 2: Verify Firebase is configured properly
    func testDiagnostic_Firebase_Configuration() {
        print("\n========================================")
        print("🔍 DIAGNOSTIC: Testing Firebase Config")
        print("========================================")
        
        // Configure Firebase if needed
        if FirebaseApp.app() == nil {
            print("📝 Configuring Firebase for the first time...")
            FirebaseApp.configure()
        } else {
            print("📝 Firebase already configured")
        }
        
        // Verify Firebase app exists
        XCTAssertNotNil(FirebaseApp.app(), "Firebase app should be configured")
        
        // Check Firebase options
        if let firebaseApp = FirebaseApp.app() {
            print("📝 Firebase App Name: \(firebaseApp.name)")
            let options = firebaseApp.options
            // Handle both String and String? for apiKey across Firebase versions
            let apiKeyStr = "\(options.apiKey)"
            let googleAppIDStr = "\(options.googleAppID)"
            let clientIDStr = options.clientID.map { "\($0)" } ?? "nil"
            let projectIDStr = options.projectID ?? "nil"
            
            print("📝 Firebase API Key: \(apiKeyStr.prefix(10))...")
            print("📝 Firebase Project ID: \(projectIDStr)")
            print("📝 Firebase App ID: \(googleAppIDStr.prefix(20))...")
            print("📝 Firebase Client ID: \(clientIDStr.prefix(20))...")
            
            // In CI, these should all be properly configured
            // In local dev, they might be placeholder values
            if apiKeyStr.contains("nil") || apiKeyStr.contains("Optional") {
                print("⚠️ Firebase API Key appears to be nil or Optional - this is expected in local dev without GoogleService-Info.plist")
            } else {
                XCTAssertFalse(apiKeyStr.isEmpty, "Firebase API Key should exist in CI")
            }
            
            XCTAssertFalse(googleAppIDStr.isEmpty, "Firebase App ID should not be empty")
        }
        
        // Check Auth instance
        let auth = Auth.auth()
        print("📝 Auth currentUser: \(auth.currentUser?.uid ?? "nil")")
        print("📝 Auth app: \(auth.app?.name ?? "nil")")
        
        print("✅ Firebase configuration verified")
        print("========================================\n")
    }
    
    /// Test 3: Test Firebase network connectivity
    func testDiagnostic_Firebase_NetworkConnectivity() {
        print("\n========================================")
        print("🔍 DIAGNOSTIC: Testing Firebase Network")
        print("========================================")
        
        // Configure Firebase if needed
        if FirebaseApp.app() == nil {
            FirebaseApp.configure()
        }
        
        let expectation = XCTestExpectation(description: "Test Firebase connectivity")
        let startTime = Date()
        
        print("📝 Attempting to create test user...")
        print("📝 Timeout: 30 seconds")
        
        let testEmail = "diagnostic-test-\(Int(Date().timeIntervalSince1970))@arbore.test"
        let testPassword = "DiagnosticTest2026!"
        
        Auth.auth().createUser(withEmail: testEmail, password: testPassword) { result, error in
            let elapsed = Date().timeIntervalSince(startTime)
            
            if let error = error {
                let nsError = error as NSError
                print("❌ Firebase createUser failed after \(String(format: "%.2f", elapsed))s")
                print("📝 Error domain: \(nsError.domain)")
                print("📝 Error code: \(nsError.code)")
                print("📝 Error description: \(error.localizedDescription)")
                print("📝 Error userInfo: \(nsError.userInfo)")
                
                // Fail the test but with diagnostic info
                XCTFail("Firebase user creation failed: \(error.localizedDescription)")
            } else {
                print("✅ Firebase createUser succeeded in \(String(format: "%.2f", elapsed))s")
                print("📝 User UID: \(result?.user.uid ?? "nil")")
                
                // Clean up: delete the test user
                result?.user.delete { deleteError in
                    if let deleteError = deleteError {
                        print("⚠️ Failed to delete diagnostic user: \(deleteError.localizedDescription)")
                    } else {
                        print("✅ Diagnostic user deleted")
                    }
                    expectation.fulfill()
                }
                return
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 30.0)
        print("========================================\n")
    }
    
    /// Test 4: Verify backend connectivity
    func testDiagnostic_Backend_Connectivity() {
        print("\n========================================")
        print("🔍 DIAGNOSTIC: Testing Backend Connection")
        print("========================================")
        
        print("📝 Backend URL: \(AppConfig.baseURL)")
        
        let expectation = XCTestExpectation(description: "Backend health check")
        let startTime = Date()
        
        guard let url = URL(string: "\(AppConfig.baseURL)/health") else {
            XCTFail("Invalid backend URL")
            return
        }
        
        print("📝 Attempting to connect to: \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        request.timeoutInterval = 10.0
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            let elapsed = Date().timeIntervalSince(startTime)
            
            if let error = error {
                print("❌ Backend connection failed after \(String(format: "%.2f", elapsed))s")
                print("📝 Error: \(error.localizedDescription)")
                XCTFail("Backend not reachable: \(error.localizedDescription)")
            } else if let httpResponse = response as? HTTPURLResponse {
                print("✅ Backend responded in \(String(format: "%.2f", elapsed))s")
                print("📝 Status code: \(httpResponse.statusCode)")
                
                if let data = data, let body = String(data: data, encoding: .utf8) {
                    print("📝 Response body: \(body)")
                }
                
                XCTAssertEqual(httpResponse.statusCode, 200, "Backend health check should return 200")
            }
            
            expectation.fulfill()
        }.resume()
        
        wait(for: [expectation], timeout: 15.0)
        print("========================================\n")
    }
}
