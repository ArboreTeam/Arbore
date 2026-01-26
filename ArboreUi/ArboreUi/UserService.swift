import FirebaseAuth
import Foundation
import Firebase

class UserService: ObservableObject {
    @Published var currentUser: User? = nil
    @Published var fetchError: String? = nil

    func fetchUser(by uid: String) async throws -> User {
        let response: UserResponse = try await NetworkManager.shared.request(
            endpoint: "/users/\(uid)",
            method: .GET
        )

        guard let user = response.user else {
            print("❌ Utilisateur absent dans la réponse")
            throw NetworkError.serverError("User not found")
        }

        await MainActor.run {
            self.currentUser = user
        }

        return user
    }

    func fetchCurrentUser() {
        guard let uid = Auth.auth().currentUser?.uid else {
            self.fetchError = "Utilisateur non connecté."
            return
        }

        Task {
            do {
                let user = try await fetchUser(by: uid)
                await MainActor.run {
                    self.currentUser = user
                    self.fetchError = nil
                }
            } catch {
                await MainActor.run {
                    self.fetchError = error.localizedDescription
                }
            }
        }
    }
}
