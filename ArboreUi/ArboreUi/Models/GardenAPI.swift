import Foundation

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case server(Int, Data)
}

final class GardenAPI {
    static let shared = GardenAPI()

    /// URL du serveur backend (centralisée dans AppConfig)
    private let baseURL = AppConfig.baseURL

    private let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        // Ton Go renvoie des dates en RFC3339/ISO-like si tu utilises time.Time (encoding/json)
        // Ça passe souvent avec .iso8601, sinon on adaptera.
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    // MARK: - Create
    func createGarden(_ garden: GardenCreateDTO) async throws -> GardenDTO {
        guard let url = URL(string: "\(baseURL)/gardens") else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try jsonEncoder.encode(garden)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server(http.statusCode, data) }

        return try jsonDecoder.decode(GardenDTO.self, from: data)
    }

    // MARK: - List (Home)
    func listGardens(uid: String) async throws -> [GardenDTO] {
        guard let encodedUID = uid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.invalidURL
        }
        guard let url = URL(string: "\(baseURL)/gardens?uid=\(encodedUID)") else { throw APIError.invalidURL }

        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server(http.statusCode, data) }

        return try jsonDecoder.decode([GardenDTO].self, from: data)
    }

    // MARK: - Get one (reopen)
    func getGarden(id: String) async throws -> GardenDTO {
        guard let url = URL(string: "\(baseURL)/gardens/\(id)") else { throw APIError.invalidURL }

        let (data, resp) = try await URLSession.shared.data(from: url)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server(http.statusCode, data) }

        return try jsonDecoder.decode(GardenDTO.self, from: data)
    }

    // MARK: - Update (PATCH-like via PUT)
    struct GardenPatch: Codable {
        var name: String?
        var wizard: GardenWizardDTO?
        var plants: [PlacedPlantDTO]?
        var thumbnailKey: String?
    }

    func updateGarden(id: String, patch: GardenPatch) async throws {
        guard let url = URL(string: "\(baseURL)/gardens/\(id)") else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "PUT"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try jsonEncoder.encode(patch)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server(http.statusCode, data) }

        _ = data
    }

    // MARK: - Delete
    func deleteGarden(id: String) async throws {
        guard let url = URL(string: "\(baseURL)/gardens/\(id)") else { throw APIError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIError.server(http.statusCode, data) }

        _ = data
    }
}
