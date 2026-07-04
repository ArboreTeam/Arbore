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

actor GeminiService {

    private static let model = "gemini-2.5-flash"
    private static let baseURL = "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent"

    private static let systemPrompt = """
    Tu es Arbore, l'assistant intelligent de jardinage intégré dans l'application Arbore. \
    Tu es un expert passionné en botanique, horticulture et aménagement de jardins.

    🌿 TON RÔLE :
    - Conseiller les utilisateurs sur le jardinage, les plantes, les arbres, les fleurs, les potagers et l'entretien des espaces verts.
    - Aider à identifier des plantes, diagnostiquer des maladies ou parasites, et recommander des traitements naturels.
    - Proposer des suggestions de plantes adaptées au climat, au sol et à l'exposition de l'utilisateur.
    - Guider sur l'arrosage, la taille, la fertilisation, le compostage et les saisons de plantation.
    - Conseiller sur l'aménagement paysager et le design de jardins.

    🚫 TES LIMITES STRICTES :
    - Tu ne réponds JAMAIS à des questions hors du domaine du jardinage, de la botanique ou de l'application Arbore.
    - Si on te pose une question hors sujet (politique, maths, code, cuisine, etc.), \
    réponds poliment : "Je suis Arbore, votre assistant jardinage 🌱 Je ne peux vous aider que sur des sujets liés au jardinage, aux plantes et à l'entretien de votre espace vert. Posez-moi une question sur vos plantes !"
    - Tu ne génères jamais de code, de scripts, ni de contenu sans rapport avec le jardinage.

    🎨 TON STYLE :
    - Ton ton est chaleureux, bienveillant et encourageant, comme un jardinier passionné qui partage son savoir.
    - Tu utilises des émojis naturels (🌱🌻🌿🌸💧☀️🪴) avec parcimonie pour rendre tes réponses vivantes.
    - Tu tutoies l'utilisateur pour créer un lien de proximité.
    - Tes réponses sont concises et pratiques, avec des conseils actionnables.
    - Quand c'est pertinent, tu structures tes réponses avec des tirets (-) pour plus de clarté.

    ✏️ FORMAT DE RÉPONSE :
    - Tu réponds en TEXTE BRUT uniquement. Pas de Markdown.
    - N'utilise JAMAIS de syntaxe Markdown : pas de ** (gras), pas de * (italique), pas de # (titres), pas de ``` (blocs de code).
    - Pour mettre en valeur un mot, utilise simplement des majuscules ou des émojis.
    - Pour les listes, utilise des tirets simples (-) ou des émojis comme puces.

    📱 CONTEXTE APPLICATION :
    - L'application Arbore permet aux utilisateurs de scanner leur jardin en 3D avec LiDAR, \
    de gérer un catalogue de plantes, et de recevoir des suggestions personnalisées.
    - Si on te demande qui tu es, présente-toi comme "Arbore, l'assistant jardinage de l'application Arbore".
    """

    func sendMessage(history: [MessageDTO], newMessage: String, imageData: Data? = nil) async throws -> String {
        let key = AppConfig.geminiAPIKey
        guard !key.isEmpty else {
            throw GeminiError.noAPIKey
        }

        guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            throw GeminiError.requestFailed(NSError(domain: "Gemini",
                code: 0, userInfo: [NSLocalizedDescriptionKey: "Clé API invalide"]))
        }

        // Build conversation contents with history
        var contents: [[String: Any]] = []
        for msg in history {
            contents.append([
                "role": msg.isUser ? "user" : "model",
                "parts": [["text": msg.content]]
            ])
        }
        // Add the new user message (with optional image)
        var newParts: [[String: Any]] = [["text": newMessage]]
        if let imageData = imageData {
            let base64 = imageData.base64EncodedString()
            newParts.append([
                "inlineData": [
                    "mimeType": "image/jpeg",
                    "data": base64
                ] as [String: Any]
            ])
        }
        contents.append([
            "role": "user",
            "parts": newParts
        ])

        let requestBody: [String: Any] = [
            "systemInstruction": [
                "parts": [["text": Self.systemPrompt]]
            ],
            "contents": contents
        ]

        guard let url = URL(string: "\(Self.baseURL)?key=\(encodedKey)") else {
            throw GeminiError.requestFailed(NSError(domain: "Gemini",
                code: 0, userInfo: [NSLocalizedDescriptionKey: "URL invalide"]))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GeminiError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                throw GeminiError.requestFailed(NSError(domain: "Gemini",
                    code: httpResponse.statusCode,
                    userInfo: [NSLocalizedDescriptionKey: "\(message)"]))
            }
            throw GeminiError.requestFailed(NSError(domain: "Gemini",
                code: httpResponse.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode) – \(body)"]))
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let candidates = json["candidates"] as? [[String: Any]],
              let first = candidates.first,
              let content = first["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            if let candidates = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["candidates"] as? [[String: Any]],
               let first = candidates.first,
               let finishReason = first["finishReason"] as? String,
               finishReason == "SAFETY" {
                throw GeminiError.blocked
            }
            throw GeminiError.invalidResponse
        }

        return Self.stripMarkdown(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Remove markdown formatting from Gemini response
    private static func stripMarkdown(_ text: String) -> String {
        var result = text
        // Remove bold **text** -> text
        result = result.replacingOccurrences(of: "\\*\\*(.+?)\\*\\*", with: "$1", options: .regularExpression)
        // Remove italic *text* -> text (not bullet points starting with * )
        result = result.replacingOccurrences(of: "(?<=\\s|^)\\*(?!\\s)(.+?)(?<!\\s)\\*(?=\\s|$|[.,;:!?])", with: "$1", options: .regularExpression)
        // Remove markdown headers ### -> (empty)
        result = result.replacingOccurrences(of: "(?m)^#{1,6}\\s+", with: "", options: .regularExpression)
        return result
    }
}
