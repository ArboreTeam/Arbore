import Foundation
import SwiftData

@Model
final class ChatConversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.conversation)
    var messages: [ChatMessage]

    init(title: String = "Nouvelle discussion") {
        self.id = UUID()
        self.title = title
        self.createdAt = Date()
        self.updatedAt = Date()
        self.messages = []
    }
}

@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var content: String
    var isUser: Bool
    var timestamp: Date

    @Attribute(.externalStorage)
    var imageData: Data?

    var conversation: ChatConversation?

    init(content: String, isUser: Bool, imageData: Data? = nil) {
        self.id = UUID()
        self.content = content
        self.isUser = isUser
        self.timestamp = Date()
        self.imageData = imageData
    }
}
