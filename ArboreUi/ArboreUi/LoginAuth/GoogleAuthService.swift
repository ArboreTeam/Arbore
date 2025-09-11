import SwiftUI
import FirebaseAuth
import GoogleSignIn
import GoogleSignInSwift
import FirebaseCore

class AuthenticationView: ObservableObject {

    @Published var isLoginSuccessed = false
    @AppStorage("isLoggedIn") var isLoggedIn = false

    func signInWithGoogle() {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            print("❌ Missing Firebase client ID.")
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("❌ Unable to get root view controller.")
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { signInResult, error in
            if let error = error {
                print("❌ Google Sign-In Error:", error.localizedDescription)
                return
            }

            guard let result = signInResult else {
                print("❌ Google Sign-In result is nil.")
                return
            }

            let idToken = result.user.idToken?.tokenString
            let accessToken = result.user.accessToken.tokenString

            guard let idToken = idToken else {
                print("❌ Missing idToken.")
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: accessToken
            )

            Auth.auth().signIn(with: credential) { authResult, error in
                if let error = error {
                    print("❌ Firebase Auth Error:", error.localizedDescription)
                    return
                }

                guard let user = authResult?.user else {
                    print("❌ Firebase user is nil")
                    return
                }

                saveUserToBackendIfNeeded(uid: user.uid, email: user.email ?? "", name: user.displayName ?? "", createdAt: Date())

                print("✅ Google user signed in:", user.email ?? "unknown")

                DispatchQueue.main.async {
                    self.isLoginSuccessed = true
                    self.isLoggedIn = true
                }
            }
        }
    }

    func reauthenticateWithGoogle(completion: @escaping (Bool) -> Void) {
        guard let clientID = FirebaseApp.app()?.options.clientID else {
            print("❌ Missing Firebase client ID.")
            completion(false)
            return
        }

        let config = GIDConfiguration(clientID: clientID)
        GIDSignIn.sharedInstance.configuration = config

        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            print("❌ Unable to get root view controller.")
            completion(false)
            return
        }

        GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController) { result, error in
            if let error = error {
                print("❌ Google Sign-In error: \(error.localizedDescription)")
                completion(false)
                return
            }

            guard let result = result else {
                print("❌ Sign-in result is nil")
                completion(false)
                return
            }

            guard let idToken = result.user.idToken?.tokenString else {
                print("❌ Missing idToken.")
                completion(false)
                return
            }
            let accessToken = result.user.accessToken.tokenString

            let credential = GoogleAuthProvider.credential(withIDToken: idToken, accessToken: accessToken)

            Auth.auth().currentUser?.reauthenticate(with: credential) { _, error in
                if let error = error {
                    print("❌ Firebase reauth error: \(error.localizedDescription)")
                    completion(false)
                } else {
                    completion(true)
                }
            }
        }
    }

    func logout() async throws {
        GIDSignIn.sharedInstance.signOut()
        try Auth.auth().signOut()
        DispatchQueue.main.async {
            self.isLoggedIn = false
        }
    }
}
