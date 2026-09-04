import Foundation

struct HouseholdSafetyProfile: Codable, Equatable {
    var avoidPetToxicity: Bool
    var avoidChildToxicity: Bool
}

struct User: Codable {
    let uid: String
    let email: String
    let name: String
    let createdAt: Date
    let photoData: String?
    let photoContentType: String?
    let banned: Bool?
    let householdSafety: HouseholdSafetyProfile?
}
