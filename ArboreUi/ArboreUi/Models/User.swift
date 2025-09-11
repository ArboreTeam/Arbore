import Foundation

struct User: Codable {
    let uid: String
    let email: String
    let name: String
    let createdAt: Date
}
