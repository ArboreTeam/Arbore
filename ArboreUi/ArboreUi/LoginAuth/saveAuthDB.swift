import Foundation
import Firebase

// MARK: - Response Models

struct UserResponse: Codable {
    let user: UserData?
    let message: String?
}

struct UserData: Codable {
    let uid: String
    let email: String
    let name: String
    let createdAt: String
    let banned: Bool?
}

// MARK: - User Management Functions

/// Envoie un utilisateur vers MongoDB via ton backend
func saveUserToBackend(uid: String, email: String, name: String, createdAt: Date) {
    Task {
        do {
            let formatter = ISO8601DateFormatter()
            let userData: [String: Any] = [
                "uid": uid,
                "email": email,
                "name": name,
                "createdAt": formatter.string(from: createdAt),
                "banned": false  // Nouveau champ requis par le backend
            ]

            if let jsonData = try? JSONSerialization.data(withJSONObject: userData, options: .prettyPrinted),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print("🚀 Payload envoyé à MongoDB :\n\(jsonString)")
            }

            let response: UserResponse = try await NetworkManager.shared.request(
                endpoint: "/users",
                method: .POST,
                body: userData
            )

            print("✅ Utilisateur enregistré dans MongoDB:", response.message ?? "success")
        } catch {
            print("❌ Erreur d'enregistrement MongoDB:", error.localizedDescription)
        }
    }
}

/// Vérifie si un utilisateur existe déjà côté MongoDB
func checkIfUserExists(uid: String) async -> Bool {
    do {
        let _: UserResponse = try await NetworkManager.shared.request(
            endpoint: "/users/\(uid)",
            method: .GET
        )
        return true  // Utilisateur trouvé
    } catch NetworkError.serverError(let message) where message.contains("404") {
        return false  // Utilisateur non trouvé
    } catch {
        print("❌ Erreur lors de la vérification de l'utilisateur:", error)
        return false
    }
}

/// Appelle `saveUserToBackend(...)` uniquement si l'utilisateur n'existe pas encore dans MongoDB
func saveUserToBackendIfNeeded(uid: String, email: String, name: String, createdAt: Date) {
    Task {
        let exists = await checkIfUserExists(uid: uid)
        if !exists {
            saveUserToBackend(uid: uid, email: email, name: name, createdAt: createdAt)
        } else {
            print("ℹ️ Utilisateur déjà existant dans MongoDB")
        }
    }
}
