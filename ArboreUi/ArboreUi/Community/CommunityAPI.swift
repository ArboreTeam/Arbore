import Foundation
import FirebaseAuth
import UIKit

enum CommunityAPIError: LocalizedError {
    case invalidURL
    case missingImageData
    case missingUser
    case invalidResponse
    case server(message: String)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL communautaire invalide."
        case .missingImageData:
            return "Impossible de préparer l'image sélectionnée."
        case .missingUser:
            return "Connectez-vous pour accéder à la communauté."
        case .invalidResponse:
            return "Réponse serveur invalide."
        case .server(let message):
            return message
        case .decoding(let error):
            return "Le feed communautaire n'a pas pu être lu: \(error.localizedDescription)"
        }
    }
}

final class CommunityAPI {
    static let shared = CommunityAPI()

    private let session: URLSession

    private init() {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        self.session = URLSession(configuration: configuration)
    }

    func fetchFeed() async throws -> [CommunityPost] {
        var request = try await authenticatedRequest(path: "/api/v1/community/feed")
        request.httpMethod = "GET"

        var (data, response) = try await session.data(for: request)
        if isUnauthorized(response) {
            request = try await authenticatedRequest(path: "/api/v1/community/feed", forceRefresh: true)
            request.httpMethod = "GET"
            (data, response) = try await session.data(for: request)
        }

        try validate(response: response, data: data)

        do {
            return try communityJSONDecoder.decode([CommunityPost].self, from: data)
        } catch {
            throw CommunityAPIError.decoding(error)
        }
    }

    func uploadPost(
        title: String,
        description: String,
        type: CommunityPostType,
        image: UIImage
    ) async throws -> CommunityPost {
        guard let imageData = image.normalizedJPEGData(compressionQuality: 0.82) else {
            throw CommunityAPIError.missingImageData
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try await authenticatedRequest(path: "/api/v1/community/posts")
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let body = MultipartFormDataBuilder(boundary: boundary)
            .addField(named: "title", value: title)
            .addField(named: "description", value: description)
            .addField(named: "type", value: type.rawValue)
            .addFile(
                named: "image",
                filename: "community-post.jpg",
                mimeType: "image/jpeg",
                data: imageData
            )
            .build()

        request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")

        var (data, response) = try await session.upload(for: request, from: body)
        if isUnauthorized(response) {
            request = try await authenticatedRequest(path: "/api/v1/community/posts", forceRefresh: true)
            request.httpMethod = "POST"
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            request.setValue(String(body.count), forHTTPHeaderField: "Content-Length")
            (data, response) = try await session.upload(for: request, from: body)
        }

        try validate(response: response, data: data)

        do {
            return try communityJSONDecoder.decode(CommunityPost.self, from: data)
        } catch {
            throw CommunityAPIError.decoding(error)
        }
    }

    private func authenticatedRequest(path: String, forceRefresh: Bool = false) async throws -> URLRequest {
        guard let url = URL(string: AppConfig.baseURL + path) else {
            throw CommunityAPIError.invalidURL
        }
        guard let user = Auth.auth().currentUser else {
            throw CommunityAPIError.missingUser
        }

        let token = try await firebaseToken(for: user, forceRefresh: forceRefresh)
        var request = URLRequest(url: url)
        request.setValue(AppConfig.apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    private func firebaseToken(for user: FirebaseAuth.User, forceRefresh: Bool) async throws -> String {
        guard forceRefresh else {
            return try await user.getIDToken()
        }

        return try await withCheckedThrowingContinuation { continuation in
            user.getIDTokenForcingRefresh(true) { token, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let token else {
                    continuation.resume(throwing: CommunityAPIError.invalidResponse)
                    return
                }

                continuation.resume(returning: token)
            }
        }
    }

    private func isUnauthorized(_ response: URLResponse) -> Bool {
        (response as? HTTPURLResponse)?.statusCode == 401
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CommunityAPIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = object["error"] as? String {
                throw CommunityAPIError.server(message: message)
            }

            throw CommunityAPIError.server(message: "Erreur serveur \(httpResponse.statusCode).")
        }
    }
}

private let communityJSONDecoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)

        if let date = CommunityDateFormatters.fractional.date(from: string) {
            return date
        }
        if let date = CommunityDateFormatters.standard.date(from: string) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Date ISO-8601 invalide: \(string)"
        )
    }
    return decoder
}()

private enum CommunityDateFormatters {
    static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let standard: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct MultipartFormDataBuilder {
    private let boundary: String
    private var data = Data()

    init(boundary: String) {
        self.boundary = boundary
    }

    func addField(named name: String, value: String) -> MultipartFormDataBuilder {
        var copy = self
        copy.data.appendUTF8("--\(boundary)\r\n")
        copy.data.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        copy.data.appendUTF8("\(value)\r\n")
        return copy
    }

    func addFile(named name: String, filename: String, mimeType: String, data fileData: Data) -> MultipartFormDataBuilder {
        var copy = self
        copy.data.appendUTF8("--\(boundary)\r\n")
        copy.data.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        copy.data.appendUTF8("Content-Type: \(mimeType)\r\n\r\n")
        copy.data.append(fileData)
        copy.data.appendUTF8("\r\n")
        return copy
    }

    func build() -> Data {
        var copy = data
        copy.appendUTF8("--\(boundary)--\r\n")
        return copy
    }
}

private extension Data {
    mutating func appendUTF8(_ string: String) {
        guard let encoded = string.data(using: .utf8) else { return }
        append(encoded)
    }
}

private extension UIImage {
    func normalizedJPEGData(compressionQuality: CGFloat) -> Data? {
        if imageOrientation == .up {
            return jpegData(compressionQuality: compressionQuality)
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let renderedImage = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return renderedImage.jpegData(compressionQuality: compressionQuality)
    }
}
