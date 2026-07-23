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
    } catch NetworkError.notFound {
        return false  // Utilisateur non trouvé
    } catch {
        print("❌ Erreur lors de la vérification de l'utilisateur:", error)
        return false
    }
}

/// Garantit que le profil Mongo existe avant d'enchaîner une opération qui en
/// dépend (notamment le stockage du refresh token Apple). Contrairement à
/// `checkIfUserExists`, une erreur réseau n'est jamais confondue avec un 404.
@discardableResult
func ensureUserInBackend(uid: String, email: String, name: String, createdAt: Date) async throws -> Bool {
    do {
        let _: UserResponse = try await NetworkManager.shared.request(
            endpoint: "/users/\(uid)",
            method: .GET
        )
        return false
    } catch NetworkError.notFound {
        try await saveUserToBackendThrowing(uid: uid, email: email, name: name, createdAt: createdAt)
        recordInitialConsents(uid: uid)
        return true
    }
}

/// Appelle `saveUserToBackend(...)` uniquement si l'utilisateur n'existe pas encore dans MongoDB
func saveUserToBackendIfNeeded(uid: String, email: String, name: String, createdAt: Date) {
    Task {
        do {
            let created = try await ensureUserInBackend(
                uid: uid,
                email: email,
                name: name,
                createdAt: createdAt
            )
            if !created {
                print("ℹ️ Utilisateur déjà existant dans MongoDB")
            }
        } catch {
            print("❌ Impossible de garantir le profil backend:", error.localizedDescription)
        }
    }
}

/// Capture initiale des consentements au signup / première création de compte (issue #218).
///
/// - `terms` + `privacy` sont posés à `true` : l'inscription vaut acceptation
///   (cf. le wrap « By signing up you agree… » de SignUpView / LoginView).
/// - Les 7 consentements granulaires sont enregistrés à leur valeur **par défaut**
///   (`ConsentDefaults`, privacy-by-default) afin de disposer d'une preuve datée
///   dès l'inscription — accountability RGPD Art. 5(2) — même si l'utilisateur
///   n'ouvre jamais l'écran Confidentialité.
///
/// Le backend dérive l'`uid` du token Firebase (le param sert au log) et exige
/// `consentType` + `version` (cf. `recordConsent`, main.go) ; l'ancienne version
/// envoyait `consentGiven`/`consentDate` sans `version` → 400 silencieux.
func recordInitialConsents(uid: String) {
    Task {
        let version = AppConfig.privacyPolicyVersion

        var snapshot: [(type: String, granted: Bool)] = [
            ("terms", true),
            ("privacy", true),
        ]
        snapshot.append(contentsOf: ConsentDefaults.initialSnapshot)

        for entry in snapshot {
            let body: [String: Any] = [
                "consentType": entry.type,
                "granted": entry.granted,
				"version": version
            ]
            do {
                try await NetworkManager.shared.requestNoResponse(
                    endpoint: "/consents",
                    method: .POST,
                    body: body
                )
            } catch {
                print("❌ Initial consent '\(entry.type)' failed:", error.localizedDescription)
            }
        }
        #if DEBUG
        print("✅ Initial consent snapshot recorded (\(snapshot.count) types) for uid=\(uid)")
        #endif
    }
}

/// Forwarde l'authorization_code Apple au backend (issue #210) afin qu'il
/// l'échange contre un refresh_token Apple et le stocke chiffré. Indispensable
/// pour révoquer le compte Apple à la suppression (Guideline 5.1.1(v)).
/// Best-effort : n'impacte jamais le login (les échecs sont seulement logués).
func linkAppleAccountWithBackend(authorizationCode: String) async throws {
    try await NetworkManager.shared.requestNoResponse(
        endpoint: "/users/me/apple-link",
        method: .POST,
        body: ["authorizationCode": authorizationCode]
    )
    #if DEBUG
    print("✅ Apple authorization_code forwardé au backend")
    #endif
}

// MARK: - Response Models

struct ConsentResponse: Codable {
    let message: String?
}
