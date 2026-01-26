//
//  ModernLoginViewModel.swift
//  ArboreUi
//
//  Created by Matribuk on 25/01/2026.
//

import Foundation
import SwiftUI
import FirebaseAuth

@MainActor
class ModernLoginViewModel: ObservableObject {
    @Published var email: String = ""
    @Published var password: String = ""
    @Published var isPasswordVisible: Bool = false
    @Published var errorMessage: String = ""
    @Published var isLoading: Bool = false
    @Published var showSignUp: Bool = false
    @Published var showReset: Bool = false
    @Published var isLoggedIn: Bool = false

    // MARK: - Validation

    var isFormValid: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var trimmedEmail: String {
        email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedPassword: String {
        password.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Actions

    func togglePasswordVisibility() {
        isPasswordVisible.toggle()
    }

    func loginUser() {
        isLoading = true
        errorMessage = ""

        guard !trimmedEmail.isEmpty && !trimmedPassword.isEmpty else {
            errorMessage = "Veuillez saisir votre email et mot de passe."
            isLoading = false
            return
        }

        Auth.auth().signIn(withEmail: trimmedEmail, password: trimmedPassword) { [weak self] result, error in
            guard let self = self else { return }

            Task { @MainActor in
                self.isLoading = false

                if let error = error as NSError? {
                    print("❌ Firebase Auth error:")
                    print("Full error: \(error)")
                    print("UserInfo: \(error.userInfo)")

                    if let underlyingError = error.userInfo[NSUnderlyingErrorKey] as? NSError,
                       let deserialized = underlyingError.userInfo["FIRAuthErrorUserInfoDeserializedResponseKey"] as? [String: Any],
                       let firebaseMessage = deserialized["message"] as? String {

                        switch firebaseMessage {
                        case "INVALID_LOGIN_CREDENTIALS":
                            self.errorMessage = "Email ou mot de passe incorrect."
                        case "TOO_MANY_ATTEMPTS_TRY_LATER":
                            self.errorMessage = "Trop de tentatives. Veuillez réessayer plus tard."
                        case "EMAIL_NOT_FOUND":
                            self.errorMessage = "Aucun compte trouvé avec cet email."
                        default:
                            self.errorMessage = "Erreur d'authentification: \(firebaseMessage)"
                        }
                    } else if let authError = AuthErrorCode(rawValue: error.code) {
                        switch authError {
                        case .wrongPassword:
                            self.errorMessage = "Email ou mot de passe incorrect."
                        case .tooManyRequests:
                            self.errorMessage = "Trop de tentatives. Veuillez réessayer plus tard."
                        case .userNotFound:
                            self.errorMessage = "Aucun compte trouvé avec cet email."
                        default:
                            self.errorMessage = "Erreur d'authentification: \(error.localizedDescription)"
                        }
                    } else {
                        self.errorMessage = "Erreur d'authentification inconnue. Veuillez réessayer."
                    }
                    return
                }

                Task {
                    if let token = try? await Auth.auth().currentUser?.getIDToken() {
                        print("🔑 Firebase Token:", token)
                    }
                }

                guard let user = result?.user else { return }

                if !user.isEmailVerified {
                    self.checkAndDeleteIfExpired(uid: user.uid)
                    self.errorMessage = "Veuillez vérifier votre email avant de vous connecter."
                    try? Auth.auth().signOut()
                    return
                }

                self.isLoggedIn = true
            }
        }
    }

    func checkAndDeleteIfExpired(uid: String) {
        Task {
            do {
                let response: UserResponse = try await NetworkManager.shared.requestWithoutAuth(
                    endpoint: "/users/\(uid)",
                    method: .GET
                )

                guard let user = response.user else {
                    print("⚠️ User not found in MongoDB")
                    return
                }

                let now = Date()
                let hoursSinceCreation = now.timeIntervalSince(user.createdAt) / 3600

                if hoursSinceCreation > 48 {
                    print("🧹 Deleting expired, unverified user...")
                    deleteAccount()
                } else {
                    print("⏱ Account still within time window")
                }
            } catch {
                print("❌ Error checking user expiration: \(error)")
            }
        }
    }

    func deleteAccount() {
        guard let user = Auth.auth().currentUser else { return }
        let uid = user.uid

        user.delete { error in
            if let error = error {
                print("❌ Error deleting Firebase account: \(error.localizedDescription)")
                return
            }

            Task {
                do {
                    try await NetworkManager.shared.requestWithoutAuthNoResponse(
                        endpoint: "/users/\(uid)",
                        method: .DELETE
                    )
                    print("✅ Account deleted from MongoDB and Firebase")
                } catch {
                    print("❌ Error deleting from MongoDB: \(error)")
                }
            }
        }
    }
}
