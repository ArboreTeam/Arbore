//
//  AppleAuthService.swift
//  ArboreUi
//
//  Issue #201 — Sign in with Apple. Mirror du `GoogleAuthService.swift`,
//  exposé sous la même surface (`signInWithApple()` + Published
//  `isLoginSuccessed` + `@AppStorage isLoggedIn`) pour que les vues
//  Login/Signup/ModernLogin puissent l'injecter sans changer leur
//  contrat.
//
//  Architecture :
//   - `ASAuthorizationController` est delegate-based, donc cette classe
//     hérite de `NSObject` et conforme les 2 protocoles
//     (`...Delegate` + `...PresentationContextProviding`).
//   - Le nonce est généré localement (random 32-byte string), passé
//     SHA-256 dans la requête Apple, puis raw au moment de l'échange
//     Firebase. Firebase vérifie que le hash dans le id_token Apple
//     correspond bien au raw nonce qu'on envoie (anti-replay).
//   - Apple ne fournit `fullName` + `email` QU'AU PREMIER SIGNUP. À
//     l'occasion on persiste sur Firebase displayName + backend Mongo
//     `users.name`. Aux signins suivants, on trust ce qu'on a déjà.
//   - Si l'user a coché « Hide my email », Apple renvoie un relay
//     address `xxx@privaterelay.appleid.com` — c'est l'email réel
//     côté Firebase + backend, les notifs envoyées dessus sont
//     relayées par Apple.
//

import SwiftUI
import AuthenticationServices
import CryptoKit
import FirebaseAuth

final class AppleAuthService: NSObject, ObservableObject {

    @Published var isLoginSuccessed = false
    @AppStorage("isLoggedIn") var isLoggedIn = false

    private var currentNonce: String?

    /// Démarre le flow Sign in with Apple. Le callback delegate gère
    /// l'enchaînement Firebase → backend → flip de `isLoggedIn`. La
    /// caller (vue SwiftUI) observe `isLoginSuccessed` pour réagir.
    func signInWithApple() {
        let nonce = randomNonceString()
        currentNonce = nonce

        let provider = ASAuthorizationAppleIDProvider()
        let request = provider.createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = sha256(nonce)

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    /// Déconnexion symétrique du `GoogleAuthService.logout()`. Apple ne
    /// fournit pas d'API « sign out » côté SDK (le credential reste
    /// valide sur l'appareil tant que l'user n'a pas révoqué l'app
    /// depuis Réglages → Apple ID → Mots de passe et sécurité). On se
    /// contente donc de virer Firebase + flip le flag local.
    func logout() async throws {
        try Auth.auth().signOut()
        await MainActor.run {
            self.isLoggedIn = false
            self.isLoginSuccessed = false
        }
    }

    // MARK: - Crypto helpers (Apple sample-code pattern)

    /// 32 caractères pseudo-aléatoires dans le charset URL-safe Apple
    /// recommande. SecRandomCopyBytes (CSPRNG) — pas d'arc4random.
    private func randomNonceString(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            let randoms: [UInt8] = (0..<16).map { _ in
                var byte: UInt8 = 0
                let status = SecRandomCopyBytes(kSecRandomDefault, 1, &byte)
                if status != errSecSuccess {
                    fatalError("Unable to generate nonce. SecRandomCopyBytes status: \(status)")
                }
                return byte
            }
            for byte in randoms where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    private func sha256(_ input: String) -> String {
        let hashed = SHA256.hash(data: Data(input.utf8))
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - ASAuthorizationControllerDelegate

extension AppleAuthService: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential else {
            print("❌ Apple Sign-In: credential is not an AppleIDCredential")
            return
        }
        guard let nonce = currentNonce else {
            // Programmer error : signInWithApple n'a pas été appelée
            // avant de recevoir un callback. Crash en debug, log en
            // release.
            assertionFailure("Apple Sign-In callback without a prior request — nonce missing.")
            return
        }
        guard let identityTokenData = appleCredential.identityToken,
              let idTokenString = String(data: identityTokenData, encoding: .utf8) else {
            print("❌ Apple Sign-In: identityToken missing or not UTF-8")
            return
        }

        // #210 — authorization_code (à usage unique) pour la révocation Apple à
        // la suppression du compte. Forwardé au backend après le signin Firebase.
        let authorizationCode = appleCredential.authorizationCode
            .flatMap { String(data: $0, encoding: .utf8) }

        // Capture du nom (premier signup uniquement, sinon nil).
        let firstName = appleCredential.fullName?.givenName ?? ""
        let lastName = appleCredential.fullName?.familyName ?? ""
        let fullName = [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ")
        let appleEmail = appleCredential.email ?? ""

        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleCredential.fullName
        )

        Auth.auth().signIn(with: credential) { [weak self] authResult, error in
            if let error = error {
                print("❌ Firebase Apple Auth Error:", error.localizedDescription)
                return
            }
            guard let user = authResult?.user else {
                print("❌ Firebase user is nil after Apple sign-in")
                return
            }

            // Premier signup : Apple a fourni le nom. On le pousse à
            // Firebase displayName (si pas déjà set) ET au backend
            // Mongo pour qu'il soit disponible côté profil. Aux
            // signins suivants, fullName est nil — on trust ce qui
            // existe déjà.
            let resolvedName = fullName.isEmpty
                ? (user.displayName ?? "")
                : fullName
            let resolvedEmail = user.email ?? appleEmail

            if !fullName.isEmpty,
               (user.displayName ?? "").isEmpty {
                let change = user.createProfileChangeRequest()
                change.displayName = fullName
                change.commitChanges { commitError in
                    if let commitError = commitError {
                        print("⚠️ Failed to commit Firebase displayName for Apple user:", commitError.localizedDescription)
                    }
                    saveUserToBackendIfNeeded(
                        uid: user.uid,
                        email: resolvedEmail,
                        name: resolvedName,
                        createdAt: Date()
                    )
                }
            } else {
                saveUserToBackendIfNeeded(
                    uid: user.uid,
                    email: resolvedEmail,
                    name: resolvedName,
                    createdAt: Date()
                )
            }

            // #210 — forward l'authorization_code pour permettre la révocation
            // du compte Apple à la suppression. Best-effort, hors chemin critique
            // de login ; se ré-exécute aux signins suivants (code frais à chaque
            // fois) si le tout premier passage a couru avec la création du user.
            if let authorizationCode = authorizationCode, !authorizationCode.isEmpty {
                linkAppleAccountWithBackend(authorizationCode: authorizationCode)
            }

            #if DEBUG
            print("✅ Apple user signed in:", resolvedEmail.isEmpty ? "unknown" : resolvedEmail)
            #endif

            DispatchQueue.main.async {
                self?.isLoginSuccessed = true
                self?.isLoggedIn = true
            }
        }
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        // ASAuthorizationError.canceled (code 1001) = user a tapé Cancel
        // dans la sheet Apple — comportement attendu, pas une erreur.
        if let asError = error as? ASAuthorizationError, asError.code == .canceled {
            print("ℹ️ Apple Sign-In cancelled by user")
            return
        }
        print("❌ Apple Sign-In Error:", error.localizedDescription)
    }
}

// MARK: - ASAuthorizationControllerPresentationContextProviding

extension AppleAuthService: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        // Trouver le UIWindow actif pour ancrer la sheet Apple. Sans
        // ça, le système throw une exception au runtime.
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first
        else {
            return ASPresentationAnchor()
        }
        return window
    }
}
