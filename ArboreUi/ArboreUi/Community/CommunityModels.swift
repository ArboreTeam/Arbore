import Foundation

enum CommunityPostType: String, CaseIterable, Identifiable, Codable {
    case beforeAfter = "before_after"
    case dreamGarden = "dream_garden"
    case tips = "tips"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .beforeAfter:
            return "Avant/Après"
        case .dreamGarden:
            return "Jardin de rêves"
        case .tips:
            return "Tips/Astuces"
        }
    }

    var systemImage: String {
        switch self {
        case .beforeAfter:
            return "square.on.square"
        case .dreamGarden:
            return "sparkles"
        case .tips:
            return "lightbulb"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")

        switch normalized {
        case "before_after", "beforeafter":
            self = .beforeAfter
        case "dream_garden", "dreamgarden":
            self = .dreamGarden
        case "tips", "tip", "astuce", "astuces":
            self = .tips
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Type de post communautaire inconnu: \(rawValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct CommunityPost: Identifiable, Codable, Equatable {
    let id: String
    let userID: String
    let type: CommunityPostType
    let title: String
    let description: String
    let imageURL: String
    let likesCount: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "userId"
        case legacyUserID = "userID"
        case type
        case title
        case description
        case imageURL = "imageUrl"
        case legacyImageURL = "imageURL"
        case likesCount
        case legacyLikesCount = "likes"
        case createdAt
        case legacyCreatedAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        userID = container.firstString(for: [.userID, .legacyUserID]) ?? ""
        title = container.firstString(for: [.title]) ?? "Publication"
        description = container.firstString(for: [.description]) ?? ""
        imageURL = container.firstString(for: [.imageURL, .legacyImageURL]) ?? ""
        likesCount = container.firstInteger(for: [.likesCount, .legacyLikesCount]) ?? 0
        createdAt = container.firstDate(for: [.createdAt, .legacyCreatedAt]) ?? Date()
        type = (try? container.decode(CommunityPostType.self, forKey: .type)) ?? .tips

        let decodedID = container.firstString(for: [.id])?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let decodedID, !decodedID.isEmpty {
            id = decodedID
        } else {
            let fallbackID = [userID, imageURL, title]
                .filter { !$0.isEmpty }
                .joined(separator: "|")
            id = fallbackID.isEmpty ? UUID().uuidString : fallbackID
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userID, forKey: .userID)
        try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encode(description, forKey: .description)
        try container.encode(imageURL, forKey: .imageURL)
        try container.encode(likesCount, forKey: .likesCount)
        try container.encode(createdAt, forKey: .createdAt)
    }
}

private struct MongoObjectID: Decodable {
    let value: String

    enum CodingKeys: String, CodingKey {
        case value = "$oid"
    }
}

private extension KeyedDecodingContainer {
    func firstString(for keys: [Key]) -> String? {
        for key in keys {
            if let value = try? decode(String.self, forKey: key) {
                return value
            }
            if let value = try? decode(Int.self, forKey: key) {
                return String(value)
            }
            if let objectID = try? decode(MongoObjectID.self, forKey: key) {
                return objectID.value
            }
        }
        return nil
    }

    func firstInteger(for keys: [Key]) -> Int? {
        for key in keys {
            if let value = try? decode(Int.self, forKey: key) {
                return value
            }
            if let value = try? decode(Double.self, forKey: key) {
                return Int(value)
            }
            if let value = try? decode(String.self, forKey: key),
               let integer = Int(value) {
                return integer
            }
        }
        return nil
    }

    func firstDate(for keys: [Key]) -> Date? {
        for key in keys {
            if let value = try? decode(Date.self, forKey: key) {
                return value
            }
        }
        return nil
    }
}
