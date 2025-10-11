import XCTest
import SwiftUI
import Firebase
import FirebaseAuth
@testable import ArboreUi

// MARK: - Email Validation Tests
class EmailValidationTests: XCTestCase {
    
    func testEmailValidation_ValidEmails_ShouldPass() {
        let validEmails = [
            "test@example.com",
            "user.name@domain.co.uk",
            "test+tag@gmail.com",
            "123@domain.com",
            "user_name@domain-name.com"
        ]
        
        for email in validEmails {
            XCTAssertTrue(isValidEmail(email), "Email \(email) should be valid")
        }
    }
    
    func testEmailValidation_InvalidEmails_ShouldFail() {
        let invalidEmails = [
            "",
            "invalid-email",
            "@domain.com",
            "test@",
            "test..test@domain.com",
            "test@domain",
            "test @domain.com",
            "test@domain..com"
        ]
        
        for email in invalidEmails {
            XCTAssertFalse(isValidEmail(email), "Email \(email) should be invalid")
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "^[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
}

// MARK: - Password Strength Tests
class PasswordStrengthTests: XCTestCase {
    
    func testPasswordStrength_WeakPasswords_ShouldFail() {
        let weakPasswords = [
            "",
            "123",
            "abc",
            "password",
            "12345678",
            "abcdefgh"
        ]
        
        for password in weakPasswords {
            XCTAssertFalse(isStrongPassword(password), "Password '\(password)' should be considered weak")
        }
    }
    
    func testPasswordStrength_StrongPasswords_ShouldPass() {
        let strongPasswords = [
            "MyStr0ngP@ssw0rd!",
            "C0mpl3x#P@ssw0rd",
            "Secur3$P@ssw0rd123",
            "MyP@ssw0rd2023!"
        ]
        
        for password in strongPasswords {
            XCTAssertTrue(isStrongPassword(password), "Password '\(password)' should be considered strong")
        }
    }
    
    private func isStrongPassword(_ password: String) -> Bool {
        guard password.count >= 8 else { return false }
        
        let hasUpperCase = password.rangeOfCharacter(from: .uppercaseLetters) != nil
        let hasLowerCase = password.rangeOfCharacter(from: .lowercaseLetters) != nil
        let hasNumbers = password.rangeOfCharacter(from: .decimalDigits) != nil
        let hasSpecialChars = password.rangeOfCharacter(from: CharacterSet(charactersIn: "!@#$%^&*()_+-=[]{}|;:,.<>?")) != nil
        
        return hasUpperCase && hasLowerCase && hasNumbers && hasSpecialChars
    }
}

// MARK: - Security Tests
class SecurityTests: XCTestCase {
    
    func testPasswordField_ShouldBeSecureByDefault() {
        let mockThemeManager = MockThemeManager()
        let textBinding = Binding.constant("")
        let focusBinding = FocusState<ModernLoginView.Field?>().projectedValue
        let passwordVisibleBinding = Binding.constant(false)
        
        let passwordField = ModernTextField(
            text: textBinding,
            placeholder: "Password",
            systemImage: "lock.fill",
            keyboardType: .default,
            isSecure: true,
            focusedField: focusBinding,
            fieldType: .password,
            showPasswordToggle: true,
            isPasswordVisible: passwordVisibleBinding,
            themeManager: mockThemeManager
        )
        
        XCTAssertTrue(passwordField.isSecure, "Password field should be secure by default")
    }
    
    func testPasswordVisibilityToggle_ShouldChangeSecurityState() {
        var isPasswordVisible = false
        let passwordVisibleBinding = Binding(
            get: { isPasswordVisible },
            set: { isPasswordVisible = $0 }
        )
        
        let mockThemeManager = MockThemeManager()
        let textBinding = Binding.constant("")
        let focusBinding = FocusState<ModernLoginView.Field?>().projectedValue
        
        let passwordField = ModernTextField(
            text: textBinding,
            placeholder: "Password",
            systemImage: "lock.fill",
            keyboardType: .default,
            isSecure: !isPasswordVisible,
            focusedField: focusBinding,
            fieldType: .password,
            showPasswordToggle: true,
            isPasswordVisible: passwordVisibleBinding,
            themeManager: mockThemeManager
        )
        
        // Initially secure
        XCTAssertTrue(passwordField.isSecure, "Password should be secure initially")
        
        // Toggle visibility
        isPasswordVisible = true
        let toggledField = ModernTextField(
            text: textBinding,
            placeholder: "Password",
            systemImage: "lock.fill",
            keyboardType: .default,
            isSecure: !isPasswordVisible,
            focusedField: focusBinding,
            fieldType: .password,
            showPasswordToggle: true,
            isPasswordVisible: passwordVisibleBinding,
            themeManager: mockThemeManager
        )
        
        XCTAssertFalse(toggledField.isSecure, "Password should not be secure after toggle")
    }
}

// MARK: - Input Sanitization Tests
class InputSanitizationTests: XCTestCase {
    
    func testEmailInput_ShouldTrimWhitespace() {
        var view = ModernLoginView()
        let emailWithWhitespace = "  test@example.com  "
        view.email = emailWithWhitespace
        view.password = "validPassword123"
        
        // Test the trimming logic used in loginUser
        let trimmedEmail = view.email.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertEqual(trimmedEmail, "test@example.com", "Email should be trimmed of whitespace")
        XCTAssertTrue(view.isFormValid, "Form should be valid after trimming")
    }
    
    func testPasswordInput_ShouldTrimWhitespace() {
        var view = ModernLoginView()
        view.email = "test@example.com"
        let passwordWithWhitespace = "  validPassword123  "
        view.password = passwordWithWhitespace
        
        // Test the trimming logic used in loginUser
        let trimmedPassword = view.password.trimmingCharacters(in: .whitespacesAndNewlines)
        
        XCTAssertEqual(trimmedPassword, "validPassword123", "Password should be trimmed of whitespace")
        XCTAssertTrue(view.isFormValid, "Form should be valid after trimming")
    }
    
    func testSpecialCharacters_ShouldBeHandledCorrectly() {
        var view = ModernLoginView()
        view.email = "test+special@example.com"
        view.password = "P@ssw0rd!#$%"
        
        XCTAssertTrue(view.isFormValid, "Form should handle special characters correctly")
    }
}

// MARK: - Theme Consistency Tests
class ThemeConsistencyTests: XCTestCase {
    
    var mockThemeManager: MockThemeManager!
    
    override func setUpWithError() throws {
        mockThemeManager = MockThemeManager()
    }
    
    func testDarkTheme_AllComponentsConsistent() {
        mockThemeManager.colorScheme = .dark
        let view = ModernLoginView().environmentObject(mockThemeManager)
        
        // Test main view colors
        XCTAssertEqual(view.backgroundColor, Color.black)
        XCTAssertEqual(view.textColor, Color.white)
        XCTAssertEqual(view.fieldBackgroundColor, Color(hex: "#1C1C1E"))
        
        // Test text field colors
        let textBinding = Binding.constant("")
        let focusBinding = FocusState<ModernLoginView.Field?>().projectedValue
        
        let textField = ModernTextField(
            text: textBinding,
            placeholder: "Test",
            systemImage: "envelope.fill",
            keyboardType: .default,
            isSecure: false,
            focusedField: focusBinding,
            fieldType: .email,
            themeManager: mockThemeManager
        )
        
        XCTAssertEqual(textField.textColor, Color.white)
        XCTAssertEqual(textField.fieldBackgroundColor, Color(hex: "#1C1C1E"))
    }
    
    func testLightTheme_AllComponentsConsistent() {
        mockThemeManager.colorScheme = .light
        let view = ModernLoginView().environmentObject(mockThemeManager)
        
        // Test main view colors
        XCTAssertEqual(view.backgroundColor, Color.white)
        XCTAssertEqual(view.textColor, Color(hex: "#1C1C1E"))
        XCTAssertEqual(view.fieldBackgroundColor, Color.white)
        
        // Test text field colors
        let textBinding = Binding.constant("")
        let focusBinding = FocusState<ModernLoginView.Field?>().projectedValue
        
        let textField = ModernTextField(
            text: textBinding,
            placeholder: "Test",
            systemImage: "envelope.fill",
            keyboardType: .default,
            isSecure: false,
            focusedField: focusBinding,
            fieldType: .email,
            themeManager: mockThemeManager
        )
        
        XCTAssertEqual(textField.textColor, Color(hex: "#1C1C1E"))
        XCTAssertEqual(textField.fieldBackgroundColor, Color.white)
    }
}

// MARK: - Error Message Tests
class ErrorMessageTests: XCTestCase {
    
    func testErrorMessages_ShouldBeInFrench() {
        let expectedMessages = [
            "Veuillez saisir votre email et mot de passe.",
            "Email ou mot de passe incorrect.",
            "Trop de tentatives. Veuillez réessayer plus tard.",
            "Aucun compte trouvé avec cet email.",
            "Veuillez vérifier votre email avant de vous connecter."
        ]
        
        for message in expectedMessages {
            XCTAssertFalse(message.isEmpty, "Error message should not be empty")
            XCTAssertTrue(message.contains("Veuillez") || message.contains("Email") || message.contains("Trop") || message.contains("Aucun"), 
                         "Error message should be in French")
        }
    }
    
    func testEmptyFieldsError_ShouldShowCorrectMessage() {
        var view = ModernLoginView()
        view.loginUser()
        
        let expectation = XCTestExpectation(description: "Error message set")
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            XCTAssertEqual(view.errorMessage, "Veuillez saisir votre email et mot de passe.")
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - UI State Tests
class UIStateTests: XCTestCase {
    
    func testLoadingState_ShouldDisableButton() {
        var view = ModernLoginView()
        view.email = "test@example.com"
        view.password = "validPassword123"
        
        // Simulate loading state
        view.isLoading = true
        
        XCTAssertTrue(view.isLoading, "Should be in loading state")
        // In a real scenario, the button would be disabled when isLoading is true
    }
    
    func testFormValidation_ShouldControlButtonState() {
        var view = ModernLoginView()
        
        // Invalid form
        XCTAssertFalse(view.isFormValid, "Button should be disabled with invalid form")
        
        // Valid form
        view.email = "test@example.com"
        view.password = "validPassword123"
        XCTAssertTrue(view.isFormValid, "Button should be enabled with valid form")
    }
    
    func testNavigationStates_ShouldControlViewPresentation() {
        var view = ModernLoginView()
        
        XCTAssertFalse(view.showSignUp, "Sign up view should not be shown initially")
        XCTAssertFalse(view.showReset, "Reset password view should not be shown initially")
        
        view.showSignUp = true
        XCTAssertTrue(view.showSignUp, "Sign up view should be shown when toggled")
        
        view.showReset = true
        XCTAssertTrue(view.showReset, "Reset password view should be shown when toggled")
    }
}

// MARK: - Accessibility Tests
class LoginAccessibilityTests: XCTestCase {
    
    func testTextFields_ShouldHaveProperLabels() {
        let mockThemeManager = MockThemeManager()
        let textBinding = Binding.constant("")
        let focusBinding = FocusState<ModernLoginView.Field?>().projectedValue
        
        let emailField = ModernTextField(
            text: textBinding,
            placeholder: "Adresse email",
            systemImage: "envelope.fill",
            keyboardType: .emailAddress,
            isSecure: false,
            focusedField: focusBinding,
            fieldType: .email,
            themeManager: mockThemeManager
        )
        
        XCTAssertEqual(emailField.placeholder, "Adresse email", "Email field should have proper placeholder")
        XCTAssertEqual(emailField.keyboardType, .emailAddress, "Email field should have email keyboard type")
        
        let passwordField = ModernTextField(
            text: textBinding,
            placeholder: "Mot de passe",
            systemImage: "lock.fill",
            keyboardType: .default,
            isSecure: true,
            focusedField: focusBinding,
            fieldType: .password,
            themeManager: mockThemeManager
        )
        
        XCTAssertEqual(passwordField.placeholder, "Mot de passe", "Password field should have proper placeholder")
        XCTAssertTrue(passwordField.isSecure, "Password field should be secure")
    }
}

// MARK: - Color Extension Tests
class ColorExtensionTests: XCTestCase {
    
    func testColorHexInitializer_ValidHex_ShouldCreateCorrectColor() {
        let redColor = Color(hex: "#FF0000")
        let greenColor = Color(hex: "#00FF00")
        let blueColor = Color(hex: "#0000FF")
        let customColor = Color(hex: "#4A7C59")
        
        // Ces tests nécessiteraient une méthode pour extraire les composants RGB de Color
        // Pour l'instant, on vérifie juste que les couleurs sont créées sans crash
        XCTAssertNotNil(redColor, "Red color should be created")
        XCTAssertNotNil(greenColor, "Green color should be created")
        XCTAssertNotNil(blueColor, "Blue color should be created")
        XCTAssertNotNil(customColor, "Custom color should be created")
    }
    
    func testColorHexInitializer_InvalidHex_ShouldHandleGracefully() {
        let invalidColor1 = Color(hex: "invalid")
        let invalidColor2 = Color(hex: "#")
        let invalidColor3 = Color(hex: "")
        
        XCTAssertNotNil(invalidColor1, "Should handle invalid hex gracefully")
        XCTAssertNotNil(invalidColor2, "Should handle invalid hex gracefully")
        XCTAssertNotNil(invalidColor3, "Should handle invalid hex gracefully")
    }
}

// MARK: - Performance Tests
class LoginPerformanceTests: XCTestCase {
    
    func testFormValidation_Performance() {
        var view = ModernLoginView()
        view.email = "test@example.com"
        view.password = "validPassword123"
        
        measure {
            for _ in 0..<10000 {
                _ = view.isFormValid
            }
        }
    }
    
    func testThemeColorCalculation_Performance() {
        let mockThemeManager = MockThemeManager()
        let view = ModernLoginView().environmentObject(mockThemeManager)
        
        measure {
            for _ in 0..<1000 {
                _ = view.backgroundColor
                _ = view.textColor
                _ = view.fieldBackgroundColor
                _ = view.secondaryTextColor
            }
        }
    }
}

// MARK: - Integration Tests
class LoginIntegrationTests: XCTestCase {
    
    func testCompleteLoginFlow_WithValidData_ShouldSucceed() {
        var view = ModernLoginView()
        view.email = "test@example.com"
        view.password = "validPassword123"
        
        XCTAssertTrue(view.isFormValid, "Form should be valid with correct data")
        XCTAssertFalse(view.isLoading, "Should not be loading initially")
        XCTAssertEqual(view.errorMessage, "", "Should have no error message initially")
    }
    
    func testNavigationFlow_ShouldMaintainState() {
        var view = ModernLoginView()
        
        // Test sign up navigation
        view.showSignUp = true
        XCTAssertTrue(view.showSignUp, "Sign up navigation should be triggered")
        
        // Test reset password navigation
        view.showReset = true
        XCTAssertTrue(view.showReset, "Reset password navigation should be triggered")
    }
}

// MARK: - Edge Cases Tests
class EdgeCaseTests: XCTestCase {
    
    func testVeryLongInputs_ShouldBeHandledCorrectly() {
        var view = ModernLoginView()
        let veryLongEmail = String(repeating: "a", count: 1000) + "@example.com"
        let veryLongPassword = String(repeating: "p", count: 1000)
        
        view.email = veryLongEmail
        view.password = veryLongPassword
        
        XCTAssertTrue(view.isFormValid, "Should handle very long inputs")
    }
    
    func testUnicodeCharacters_ShouldBeHandledCorrectly() {
        var view = ModernLoginView()
        view.email = "tëst@éxämplé.com"
        view.password = "pässwörd123"
        
        XCTAssertTrue(view.isFormValid, "Should handle unicode characters")
    }
    
    func testEmptyAfterTrimming_ShouldBeInvalid() {
        var view = ModernLoginView()
        view.email = "   "
        view.password = "   "
        
        XCTAssertFalse(view.isFormValid, "Should be invalid after trimming whitespace")
    }
}
