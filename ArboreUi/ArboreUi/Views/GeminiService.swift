import Foundation

enum GeminiError: Error {
    case noAPIKey
    case invalidResponse
    case requestFailed(Error)
    case blocked
}

extension GeminiError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .noAPIKey:
            return "Clé API Gemini manquante"
        case .invalidResponse:
            return "Réponse invalide de l'API Gemini"
        case .requestFailed(let error):
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        case .blocked:
            return "Réponse bloquée pour des raisons de sécurité"
        }
    }
}

struct ChatBackendResponse: Decodable {
    let reply: String
}

actor GeminiService {

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
            throw GeminiError.invalidResponse
        }
        
        do {
            let response: ChatBackendResponse = try await NetworkManager.shared.request(
                endpoint: "/chat",
                method: .POST,
                body: payloadDict
            )
            return response.reply
        } catch {
            throw GeminiError.requestFailed(error)
        }
    }
}
