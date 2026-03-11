import Foundation
import Firebase

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

/// Enregistre les consentements initiaux (Terms + Privacy) lors de l'inscription
func recordInitialConsents(uid: String, acceptedTerms: Bool, acceptedPrivacy: Bool) {
    Task {
        do {
            // Get user's IP address and user agent
            let ipAddress = await getUserIPAddress()
            let userAgent = "ArboreApp/iOS"

            // Record Terms of Service consent
            if acceptedTerms {
                let termsConsent: [String: Any] = [
                    "uid": uid,
                    "consentType": "terms",
                    "consentGiven": true,
                    "consentDate": ISO8601DateFormatter().string(from: Date()),
                    "ipAddress": ipAddress,
                    "userAgent": userAgent
                ]

                let _: ConsentResponse = try await NetworkManager.shared.request(
                    endpoint: "/consents",
                    method: .POST,
                    body: termsConsent
                )
                print("✅ Terms consent recorded")
            }

            // Record Privacy Policy consent
            if acceptedPrivacy {
                let privacyConsent: [String: Any] = [
                    "uid": uid,
                    "consentType": "privacy",
                    "consentGiven": true,
                    "consentDate": ISO8601DateFormatter().string(from: Date()),
                    "ipAddress": ipAddress,
                    "userAgent": userAgent
                ]

                let _: ConsentResponse = try await NetworkManager.shared.request(
                    endpoint: "/consents",
                    method: .POST,
                    body: privacyConsent
                )
                print("✅ Privacy consent recorded")
            }
        } catch {
            print("❌ Error recording consents:", error.localizedDescription)
        }
    }
}

/// Récupère l'adresse IP de l'utilisateur
private func getUserIPAddress() async -> String {
    do {
        let (data, _) = try await URLSession.shared.data(from: URL(string: "https://api.ipify.org?format=json")!)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let ip = json["ip"] {
            return ip
        }
    } catch {
        print("❌ Failed to get IP address:", error.localizedDescription)
    }
    return "unknown"
}

// MARK: - Response Models

struct ConsentResponse: Codable {
    let message: String?
}
