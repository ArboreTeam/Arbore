//
//  NetworkManager.swift
//  ArboreUi
//
//  Created by Matribuk on 25/01/2026.
//

import Foundation
import FirebaseAuth

enum HTTPMethod: String {
    case GET, POST, PUT, DELETE
}

enum NetworkError: Error {
    case invalidURL
    case noUser
    case noToken
    case serverError(String)
    case unauthorized
    case forbidden
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
        case .decodingError(let error):
            return "Erreur de décodage: \(error.localizedDescription)"
        }
    }
}

class NetworkManager {
    static let shared = NetworkManager()

    private init() {}

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

        guard let currentUser = Auth.auth().currentUser else {
            throw NetworkError.noUser
        }

        do {
            let idToken = try await currentUser.getIDToken()
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
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

        let (data, response) = try await URLSession.shared.data(for: request)

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
                print("❌ Erreur décodage:", error)
                print("📄 Data reçue:", String(data: data, encoding: .utf8) ?? "nil")
                throw NetworkError.decodingError(error)
            }

        case 401:
            print("❌ 401 Unauthorized - Token invalide")
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

    func requestNoResponse(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: [String: Any]? = nil
    ) async throws {
        let _: EmptyResponse = try await request(endpoint: endpoint, method: method, body: body)
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

        guard let currentUser = Auth.auth().currentUser else {
            throw NetworkError.noUser
        }

        let idToken = try await currentUser.getIDToken()
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        if let body = body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NetworkError.serverError("Réponse invalide")
        }

        switch httpResponse.statusCode {
        case 200...299:
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NetworkError.decodingError(NSError(domain: "NetworkManager", code: -1))
            }
            return json

        case 401:
            throw NetworkError.unauthorized

        case 403:
            throw NetworkError.forbidden

        default:
            if let errorData = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errorMessage = errorData["error"] as? String {
                throw NetworkError.serverError(errorMessage)
            }
            throw NetworkError.serverError("Status code: \(httpResponse.statusCode)")
        }
    }
}

// MARK: - Helper Models

struct EmptyResponse: Codable {}
