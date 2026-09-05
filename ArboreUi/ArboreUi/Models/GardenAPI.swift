import Foundation

enum APIError: Error {
    case invalidURL
    case invalidResponse
    case server(Int, Data)
}

final class GardenAPI {
    static let shared = GardenAPI()

    struct ClimateProfileResponse: Codable {
        let siteProfile: GardenSiteProfileDTO
        let attribution: String?
    }

    private struct ClimateProfileRequest: Codable {
        let location: GardenLocationDTO
    }

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
    // Backend returns JSON `null` when the user has no gardens instead of `[]`,
    // which fails to decode as `[GardenDTO]`. Wrap the raw array in an optional
    // so `null` decodes to `nil`, then map to an empty array.
    func listGardens() async throws -> [GardenDTO] {
        let result: [GardenDTO]? = try await NetworkManager.shared.request(
            endpoint: "/gardens",
            method: .GET
        )
        return result ?? []
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
        var name: String? = nil
        var wizard: GardenWizardDTO? = nil
        var plants: [PlacedPlantDTO]? = nil
        var thumbnailKey: String? = nil
        var measurements: GardenMeasurementsDTO? = nil
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

    // MARK: - Climate enrichment
    func fetchClimateProfile(for location: GardenLocationDTO) async throws -> ClimateProfileResponse {
        let request = ClimateProfileRequest(location: location)
        let jsonData = try JSONEncoder().encode(request)
        guard let bodyDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw APIError.invalidURL
        }

        return try await NetworkManager.shared.request(
            endpoint: "/climate/profile",
            method: .POST,
            body: bodyDict
        )
    }
}
