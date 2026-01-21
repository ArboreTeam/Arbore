import Foundation
import Firebase

/// Envoie un utilisateur vers MongoDB via ton backend
func saveUserToBackend(uid: String, email: String, name: String, createdAt: Date) {
    guard let url = URL(string: AppConfig.usersEndpoint) else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let formatter = ISO8601DateFormatter()
    let user: [String: Any] = [
        "uid": uid,
        "email": email,
        "name": name,
        "createdAt": formatter.string(from: createdAt)
    ]

    if let jsonData = try? JSONSerialization.data(withJSONObject: user, options: .prettyPrinted),
    let jsonString = String(data: jsonData, encoding: .utf8) {
        print("🚀 Payload envoyé à MongoDB :\n\(jsonString)")
    }


    guard let body = try? JSONSerialization.data(withJSONObject: user, options: []) else { return }
    request.httpBody = body

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("❌ Erreur d’enregistrement MongoDB :", error)
            return
        }

        if let response = response as? HTTPURLResponse, response.statusCode == 200 {
            print("✅ Utilisateur enregistré dans MongoDB")
        } else {
            print("⚠️ Réponse inattendue du serveur MongoDB")
        }
    }.resume()
}

/// Vérifie si un utilisateur existe déjà côté MongoDB
func checkIfUserExists(uid: String, completion: @escaping (Bool) -> Void) {
    guard let url = URL(string: "\(AppConfig.usersEndpoint)/\(uid)") else { return }

    var request = URLRequest(url: url)
    request.httpMethod = "GET"

    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error = error {
            print("❌ Erreur lors de la vérification de l'utilisateur :", error)
            completion(false)
            return
        }

        if let httpResponse = response as? HTTPURLResponse {
            switch httpResponse.statusCode {
            case 200:
                completion(true)  // utilisateur trouvé
            case 404:
                completion(false) // utilisateur non trouvé
            default:
                print("⚠️ Réponse inattendue : \(httpResponse.statusCode)")
                completion(false)
            }
        }
    }.resume()
}

/// Appelle `saveUserToBackend(...)` uniquement si l’utilisateur n’existe pas encore dans MongoDB
func saveUserToBackendIfNeeded(uid: String, email: String, name: String, createdAt: Date) {
    checkIfUserExists(uid: uid) { exists in
        if !exists {
            saveUserToBackend(uid: uid, email: email, name: name, createdAt: createdAt)
        } else {
            print("ℹ️ Utilisateur déjà existant dans MongoDB")
        }
    }
}
