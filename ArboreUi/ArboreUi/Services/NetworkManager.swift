//
//  NetworkManager.swift
//  ArboreUi
//
//  Created by Matribuk on 25/01/2026.
//

import Foundation
import FirebaseAuth

enum HTTPMethod: String {
    case GET, POST, PUT, PATCH, DELETE
}

enum NetworkError: Error {
    case invalidURL
    case noUser
    case noToken
    case serverError(String)
    case unauthorized
    case forbidden
    case emailNotVerified
    case notFound
    case decodingError(Error)
}

extension NetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL invalide"
        case .noUser:
            return "Utilisateur non connecté"
        case .noToken:
            return "Token d'authentification manquant"
        case .serverError(let message):
            return "Erreur serveur: \(message)"
        case .unauthorized:
            return "Non autorisé - Token invalide ou expiré"
        case .forbidden:
            return "Accès interdit - Compte banni ou permissions insuffisantes"
        case .emailNotVerified:
            return "Email non vérifié - vérifie ta boîte mail pour activer ton compte"
        case .notFound:
            return "Ressource introuvable"
        case .decodingError(let error):
            return "Erreur de décodage: \(error.localizedDescription)"
        }
    }
}

class NetworkManager {
    static let shared = NetworkManager()

    private init() {}

    // MARK: - Public Properties

    /// URL de base du backend (exposée pour ModelCacheManager)
    var baseURL: String {
        AppConfig.baseURL
    }

    /// Clé API (exposée pour ModelCacheManager)
    var apiKey: String {
        AppConfig.apiKey
    }

    /// URLSession dédiée aux appels backend. Timeouts courts pour éviter
    /// que le premier clic catalogue bloque 60 s quand iCloud Private
    /// Relay tente de proxy-fier un HTTP non chiffré via son infra QUIC
    /// et échoue (erreur -1001 avec _NSURLErrorPrivacyProxyFailureKey=true).
    /// Un retry automatique est géré par `performWithRetry` ci-dessous.
    private lazy var httpSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 30
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    /// Exécute la requête avec un retry unique sur timeout réseau.
    /// Les timeouts Private Relay au premier appel sont suivis d'un
    /// second essai sur connexion fraîche qui passe habituellement.
    private func performWithRetry(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await httpSession.data(for: request)
        } catch let error as URLError where error.code == .timedOut || error.code == .cannotConnectToHost || error.code == .networkConnectionLost {
            print("⚠️ Network error (\(error.code.rawValue)) on first try, retrying once…")
            return try await httpSession.data(for: request)
        }
    }

    /// Token Firebase du user courant. Le SDK rafraîchit automatiquement
    /// l'ID token quand il est expiré ou proche de l'expiration : inutile
    /// de forcer un round-trip réseau à chaque requête. Le refresh forcé
    /// est réservé au retry après un 401 (cf. `getFreshFirebaseToken`).
    func getFirebaseToken() async throws -> String {
        guard let currentUser = Auth.auth().currentUser else {
            throw NetworkError.noUser
        }
        return try await currentUser.getIDToken()
    }

    /// Force un rafraîchissement du token Firebase pour traiter les 401 dus
    /// à un ID token en cache invalidé côté backend. Appelé uniquement en
    /// retry, jamais sur le chemin nominal.
    private func getFreshFirebaseToken() async throws -> String {
        guard let currentUser = Auth.auth().currentUser else {
            throw NetworkError.noUser
        }
        return try await withCheckedThrowingContinuation { continuation in
            currentUser.getIDTokenForcingRefresh(true) { token, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let token = token else {
                    continuation.resume(throwing: NetworkError.noToken)
                    return
                }

                continuation.resume(returning: token)
            }
        }
    }

    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: [String: Any]? = nil
    ) async throws -> T {

        guard let url = URL(string: AppConfig.baseURL + endpoint) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        guard Auth.auth().currentUser != nil else {
            throw NetworkError.noUser
        }

        do {
            let idToken = try await getFirebaseToken()
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

            // 🔍 DEBUG: Decode JWT claims to diagnose 401 errors
            #if DEBUG
            let parts = idToken.split(separator: ".")
            if parts.count >= 2 {
                var payload = String(parts[1])
                // JWT base64url → base64
                payload = payload.replacingOccurrences(of: "-", with: "+")
                                 .replacingOccurrences(of: "_", with: "/")
                while payload.count % 4 != 0 { payload.append("=") }
                if let data = Data(base64Encoded: payload),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    print("🔍 TOKEN DEBUG — aud:", json["aud"] ?? "nil")
                    print("🔍 TOKEN DEBUG — iss:", json["iss"] ?? "nil")
                    print("🔍 TOKEN DEBUG — sub (uid):", json["sub"] ?? "nil")
                    if let exp = json["exp"] as? TimeInterval {
                        let expDate = Date(timeIntervalSince1970: exp)
                        print("🔍 TOKEN DEBUG — exp:", expDate, "(now:", Date(), ")")
                    }
                    if let firebase = json["firebase"] as? [String: Any] {
                        print("🔍 TOKEN DEBUG — firebase.sign_in_provider:", firebase["sign_in_provider"] ?? "nil")
                    }
                }
            }
            #endif
        } catch {
            print("❌ Erreur lors de la récupération du token Firebase:", error)
            throw NetworkError.noToken
        }

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw NetworkError.serverError("Erreur sérialisation JSON: \(error.localizedDescription)")
            }
        }

        var (data, response) = try await performWithRetry(request)

        guard var httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError("Réponse invalide")
        }

        // 401 → l'ID token en cache a peut-être été invalidé côté backend.
        // On force UN refresh et on retente une seule fois. Le chemin nominal
        // reste sans refresh forcé (perf : pas de round-trip Firebase par appel).
        if httpResponse.statusCode == 401 {
            let freshToken = try await getFreshFirebaseToken()
            request.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await performWithRetry(request)
            guard let retried = response as? HTTPURLResponse else {
                throw NetworkError.serverError("Réponse invalide")
            }
            httpResponse = retried
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(T.self, from: data)
                return decoded
            } catch {
                #if DEBUG
                print("❌ Erreur décodage:", error)
                print("📄 Data reçue:", String(data: data, encoding: .utf8) ?? "nil")
                #endif
                throw NetworkError.decodingError(error)
            }

        case 401:
            #if DEBUG
            if let errorStr = String(data: data, encoding: .utf8) {
                print("❌ 401 Unauthorized - Backend response:", errorStr)
            } else {
                print("❌ 401 Unauthorized - Token invalide")
            }
            #endif
            throw NetworkError.unauthorized

        case 403:
            print("❌ 403 Forbidden - Accès refusé")
            throw forbiddenError(from: data)

        case 404:
            throw NetworkError.notFound

        default:
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                throw NetworkError.serverError(errorMessage)
            }
            throw NetworkError.serverError("Status code: \(httpResponse.statusCode)")
        }
    }

    func requestNoResponse(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: [String: Any]? = nil
    ) async throws {
        let _: EmptyResponse = try await request(endpoint: endpoint, method: method, body: body)
    }

    /// #110 : un 403 du backend peut signifier `EMAIL_NOT_VERIFIED` (le token
    /// Firebase est valide mais l'email n'est pas vérifié). Dans ce cas, on coupe
    /// la session (le compte ne devrait pas être connecté tant qu'il n'est pas
    /// vérifié) et on remonte une erreur dédiée. Sinon, c'est un vrai forbidden.
    private func forbiddenError(from data: Data) -> NetworkError {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           (obj["code"] as? String) == "EMAIL_NOT_VERIFIED" {
            DispatchQueue.main.async {
                try? Auth.auth().signOut()
                UserDefaults.standard.set(false, forKey: "isLoggedIn")
            }
            return .emailNotVerified
        }
        return .forbidden
    }

    func requestDictionary(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: [String: Any]? = nil
    ) async throws -> [String: Any] {

        guard let url = URL(string: AppConfig.baseURL + endpoint) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        guard Auth.auth().currentUser != nil else {
            throw NetworkError.noUser
        }

        let idToken = try await getFirebaseToken()
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        var (data, response) = try await performWithRetry(request)

        guard var httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError("Réponse invalide")
        }

        // 401 → refresh forcé + un seul retry (cf. request<T>).
        if httpResponse.statusCode == 401 {
            let freshToken = try await getFreshFirebaseToken()
            request.setValue("Bearer \(freshToken)", forHTTPHeaderField: "Authorization")
            (data, response) = try await performWithRetry(request)
            guard let retried = response as? HTTPURLResponse else {
                throw NetworkError.serverError("Réponse invalide")
            }
            httpResponse = retried
        }

        switch httpResponse.statusCode {
        case 200...299:
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NetworkError.decodingError(NSError(domain: "NetworkManager", code: -1))
            }
            return json

        case 401:
            #if DEBUG
            if let errorStr = String(data: data, encoding: .utf8) {
                print("❌ 401 Unauthorized - Backend response:", errorStr)
            }
            #endif
            throw NetworkError.unauthorized

        case 403:
            throw forbiddenError(from: data)

        case 404:
            throw NetworkError.notFound

        default:
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                throw NetworkError.serverError(errorMessage)
            }
            throw NetworkError.serverError("Status code: \(httpResponse.statusCode)")
        }
    }

    // MARK: - Request without Firebase Auth (API Key only)

    /// Requête avec API Key uniquement (sans token Firebase)
    /// Utilisé pour les endpoints publics protégés par API Key uniquement
    func requestWithoutAuth<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: [String: Any]? = nil
    ) async throws -> T {

        guard let url = URL(string: AppConfig.baseURL + endpoint) else {
            throw NetworkError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue

        // SEULEMENT l'API Key, pas de Firebase token
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do {
                request.httpBody = try JSONSerialization.data(withJSONObject: body)
            } catch {
                throw NetworkError.serverError("Erreur sérialisation JSON: \(error.localizedDescription)")
            }
        }

        let (data, response) = try await performWithRetry(request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError("Réponse invalide")
        }

        switch httpResponse.statusCode {
        case 200...299:
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decoded = try decoder.decode(T.self, from: data)
                return decoded
            } catch {
                #if DEBUG
                print("❌ Erreur décodage:", error)
                print("📄 Data reçue:", String(data: data, encoding: .utf8) ?? "nil")
                #endif
                throw NetworkError.decodingError(error)
            }

        case 401:
            print("❌ 401 Unauthorized - API Key invalide ou manquante")
            throw NetworkError.unauthorized

        case 403:
            print("❌ 403 Forbidden - Accès refusé")
            throw NetworkError.forbidden

        default:
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                throw NetworkError.serverError(errorMessage)
            }
            throw NetworkError.serverError("Status code: \(httpResponse.statusCode)")
        }
    }

    /// Requête sans réponse attendue (API Key uniquement)
    func requestWithoutAuthNoResponse(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: [String: Any]? = nil
    ) async throws {
        let _: EmptyResponse = try await requestWithoutAuth(endpoint: endpoint, method: method, body: body)
    }
}

// MARK: - Helper Models

struct EmptyResponse: Codable {}
