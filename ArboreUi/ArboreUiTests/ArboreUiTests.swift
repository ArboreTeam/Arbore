//
//  ArboreUiTests.swift
//  ArboreUiTests
//
//  Created by Hugo Rath on 14/03/2025.
//

import Testing
import XCTest
@testable import ArboreUi

enum LiveIntegrationTestGate {
    static let environmentKey = "ARBORE_RUN_LIVE_INTEGRATION_TESTS"

    static func requireEnabled() throws {
        guard ProcessInfo.processInfo.environment[environmentKey] == "1" else {
            throw XCTSkip(
                "Live Firebase/backend integration test skipped. Set \(environmentKey)=1 and run with a signed test host."
            )
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
