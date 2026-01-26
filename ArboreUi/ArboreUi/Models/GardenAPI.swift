import Foundation

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case server(Int, Data)
}

final class GardenAPI {
    static let shared = GardenAPI()

    // MARK: - Create
    func createGarden(_ garden: GardenCreateDTO) async throws -> GardenDTO {
        // Convert DTO to dictionary for NetworkManager
        let jsonData = try JSONEncoder().encode(garden)
        guard let bodyDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw APIError.invalidURL
        }

        return try await NetworkManager.shared.request(
            endpoint: "/gardens",
            method: .POST,
            body: bodyDict
        )
    }

    // MARK: - List (Home)
    func listGardens(uid: String) async throws -> [GardenDTO] {
        guard let encodedUID = uid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw APIError.invalidURL
        }

        return try await NetworkManager.shared.request(
            endpoint: "/gardens?uid=\(encodedUID)",
            method: .GET
        )
    }

    // MARK: - Get one (reopen)
    func getGarden(id: String) async throws -> GardenDTO {
        return try await NetworkManager.shared.request(
            endpoint: "/gardens/\(id)",
            method: .GET
        )
    }

    // MARK: - Update (PATCH-like via PUT)
    struct GardenPatch: Codable {
        var name: String?
        var wizard: GardenWizardDTO?
        var plants: [PlacedPlantDTO]?
        var thumbnailKey: String?
    }

    func updateGarden(id: String, patch: GardenPatch) async throws {
        // Convert patch to dictionary
        let jsonData = try JSONEncoder().encode(patch)
        guard let bodyDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw APIError.invalidURL
        }

        try await NetworkManager.shared.requestNoResponse(
            endpoint: "/gardens/\(id)",
            method: .PUT,
            body: bodyDict
        )
    }

    // MARK: - Delete
    func deleteGarden(id: String) async throws {
        try await NetworkManager.shared.requestNoResponse(
            endpoint: "/gardens/\(id)",
            method: .DELETE
        )
    }
}
