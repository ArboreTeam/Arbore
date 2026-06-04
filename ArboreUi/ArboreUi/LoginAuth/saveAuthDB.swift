import Foundation
import Firebase

// MARK: - User Management Functions

/// Envoie un utilisateur vers MongoDB via ton backend (fire-and-forget, ne throw pas).
/// Pour la signup avec rollback, utiliser `saveUserToBackendThrowing` à la place.
func saveUserToBackend(uid: String, email: String, name: String, createdAt: Date) {
    Task {
        do {
            try await saveUserToBackendThrowing(uid: uid, email: email, name: name, createdAt: createdAt)
        } catch {
            print("❌ Erreur d'enregistrement MongoDB:", error.localizedDescription)
        }
    }
}

/// Variante async/throws : remonte les erreurs au caller pour décider d'un rollback
/// (cf. SignUpView qui supprime le Firebase user si POST /users échoue).
/// Retry sur 5xx avec backoff exponentiel ; 4xx remonte tout de suite.
func saveUserToBackendThrowing(uid: String, email: String, name: String, createdAt: Date) async throws {
    let formatter = ISO8601DateFormatter()
    let userData: [String: Any] = [
        "email": email,
        "name": name,
        "createdAt": formatter.string(from: createdAt),
        "banned": false
    ]

    let maxAttempts = 3
    var lastError: Error?

    for attempt in 1...maxAttempts {
        do {
            let response: UserResponse = try await NetworkManager.shared.request(
                endpoint: "/users",
                method: .POST,
                body: userData
            )
            #if DEBUG
            print("✅ Utilisateur enregistré dans MongoDB (uid=\(uid)):", response.message ?? "success")
            #endif
            return
        } catch NetworkError.unauthorized, NetworkError.forbidden {
            // 401/403: clé API ou token invalide — retry inutile, on remonte.
            throw NetworkError.unauthorized
        } catch let error as NetworkError {
            lastError = error
            if attempt < maxAttempts, isTransient(error) {
                let delayNs = UInt64(pow(2.0, Double(attempt - 1)) * 500_000_000)
                print("⏳ POST /users échec (\(error.localizedDescription)), retry \(attempt)/\(maxAttempts - 1) dans \(delayNs / 1_000_000)ms")
                try? await Task.sleep(nanoseconds: delayNs)
                continue
            }
            throw error
        }
    }

    throw lastError ?? NetworkError.serverError("Inconnue")
}

private func isTransient(_ error: NetworkError) -> Bool {
    if case .serverError(let message) = error {
        // Heuristique: les messages venant du backend Gin commencent souvent par
        // "Status code: 5xx" pour les codes non interceptés ailleurs.
        return message.contains("Status code: 5")
    }
    return false
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

/// Forwarde l'authorization_code Apple au backend (issue #210) afin qu'il
/// l'échange contre un refresh_token Apple et le stocke chiffré. Indispensable
/// pour révoquer le compte Apple à la suppression (Guideline 5.1.1(v)).
/// Best-effort : n'impacte jamais le login (les échecs sont seulement logués).
func linkAppleAccountWithBackend(authorizationCode: String) {
    Task {
        do {
            try await NetworkManager.shared.requestNoResponse(
                endpoint: "/users/me/apple-link",
                method: .POST,
                body: ["authorizationCode": authorizationCode]
            )
            #if DEBUG
            print("✅ Apple authorization_code forwardé au backend")
            #endif
        } catch {
            print("⚠️ apple-link forward échoué:", error.localizedDescription)
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
