import Foundation

enum LLMError: Error {
    case noAPIKey
    case invalidResponse
    case requestFailed(Error)
    case blocked
}

extension LLMError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return L10n.t("CHATBOT_ERROR_UNAVAILABLE")
        case .invalidResponse:
            return L10n.t("CHATBOT_ERROR_INVALID")
        case .requestFailed(let error):
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        case .blocked:
            return L10n.t("CHATBOT_ERROR_BLOCKED")
        }
    }
}

struct ChatBackendResponse: Decodable {
    let reply: String
}

actor LLMService {

    func sendMessage(history: [MessageDTO], newMessage: String, imageData: Data? = nil) async throws -> String {
        // Encode base64 image if present
        let base64Image = imageData?.base64EncodedString()
        
        struct ChatRequestPayload: Encodable {
            let history: [ChatMessagePayload]
            let newMessage: String
            let imageData: String?
        }
        
        struct ChatMessagePayload: Encodable {
            let content: String
            let isUser: Bool
        }
        
        let historyPayload = history.map { ChatMessagePayload(content: $0.content, isUser: $0.isUser) }
        let payload = ChatRequestPayload(history: historyPayload, newMessage: newMessage, imageData: base64Image)
        
        // Encode payload as Dictionary for NetworkManager
        guard let payloadData = try? JSONEncoder().encode(payload),
              let payloadDict = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any] else {
            throw LLMError.invalidResponse
        }
        
        do {
            let response: ChatBackendResponse = try await NetworkManager.shared.request(
                endpoint: "/chat",
                method: .POST,
                body: payloadDict
            )
            return response.reply
        } catch {
            throw LLMError.requestFailed(error)
        }
    }
}
