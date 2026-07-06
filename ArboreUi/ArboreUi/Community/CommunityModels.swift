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
        case type
        case title
        case description
        case imageURL = "imageUrl"
        case likesCount
        case createdAt
    }
}
