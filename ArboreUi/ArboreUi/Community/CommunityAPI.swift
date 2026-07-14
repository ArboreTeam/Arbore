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
            return try CommunityPayloadDecoder.decodeFeed(from: data)
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
        guard let imageData = image.communityUploadJPEGData() else {
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
            return try CommunityPayloadDecoder.decodePost(from: data)
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
            if httpResponse.statusCode == 413 {
                throw CommunityAPIError.server(
                    message: "La photo est trop volumineuse pour le serveur. Choisissez une autre image ou réessayez."
                )
            }

            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = object["error"] as? String {
                throw CommunityAPIError.server(message: message)
            }

            throw CommunityAPIError.server(message: "Erreur serveur \(httpResponse.statusCode).")
        }
    }
}

enum CommunityPayloadDecoder {
    static func decodeFeed(from data: Data) throws -> [CommunityPost] {
        let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let decoder = makeCommunityJSONDecoder()

        switch root {
        case is NSNull:
            return []
        case is [Any]:
            return try decoder.decode([CommunityPost].self, from: data)
        case is [String: Any]:
            return try decoder.decode(CommunityFeedEnvelope.self, from: data).posts
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: [], debugDescription: "Format de feed communautaire inattendu.")
            )
        }
    }

    static func decodePost(from data: Data) throws -> CommunityPost {
        let decoder = makeCommunityJSONDecoder()
        let root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])

        if let object = root as? [String: Any],
           object["post"] != nil || (object["data"] != nil && object["title"] == nil) {
            return try decoder.decode(CommunityPostEnvelope.self, from: data).post
        }

        return try decoder.decode(CommunityPost.self, from: data)
    }
}

private struct CommunityFeedEnvelope: Decodable {
    let posts: [CommunityPost]

    enum CodingKeys: String, CodingKey {
        case posts
        case feed
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        for key in [CodingKeys.posts, .feed] where container.contains(key) {
            posts = try container.decodeIfPresent([CommunityPost].self, forKey: key) ?? []
            return
        }

        if container.contains(.data) {
            if let posts = try? container.decode([CommunityPost].self, forKey: .data) {
                self.posts = posts
                return
            }
            if let nested = try? container.decode(CommunityFeedEnvelope.self, forKey: .data) {
                posts = nested.posts
                return
            }
            if try container.decodeNil(forKey: .data) {
                posts = []
                return
            }
        }

        throw DecodingError.keyNotFound(
            CodingKeys.posts,
            .init(codingPath: decoder.codingPath, debugDescription: "Aucun tableau de publications dans la réponse.")
        )
    }
}

private struct CommunityPostEnvelope: Decodable {
    let post: CommunityPost

    enum CodingKeys: String, CodingKey {
        case post
        case data
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let post = try container.decodeIfPresent(CommunityPost.self, forKey: .post) {
            self.post = post
        } else {
            post = try container.decode(CommunityPost.self, forKey: .data)
        }
    }
}

private func makeCommunityJSONDecoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()

        if let timestamp = try? container.decode(Double.self) {
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
            return Date(timeIntervalSince1970: seconds)
        }

        if let string = try? container.decode(String.self) {
            if let timestamp = Double(string) {
                let seconds = timestamp > 10_000_000_000 ? timestamp / 1_000 : timestamp
                return Date(timeIntervalSince1970: seconds)
            }
            if let date = CommunityDateFormatters.fractional.date(from: string) {
                return date
            }
            if let date = CommunityDateFormatters.standard.date(from: string) {
                return date
            }
        }

        if let mongoDate = try? decoder.container(keyedBy: MongoDateKeys.self),
           let date = try mongoDate.decodeIfPresent(Date.self, forKey: .date) {
            return date
        }

        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Date communautaire invalide."
        )
    }
    return decoder
}

private enum MongoDateKeys: String, CodingKey {
    case date = "$date"
}

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

extension UIImage {
    func communityUploadJPEGData(
        maxPixelDimension: CGFloat = 1_600,
        maxByteCount: Int = 850_000
    ) -> Data? {
        guard maxPixelDimension > 0, maxByteCount > 0 else { return nil }

        let sourceSize = CGSize(
            width: max(size.width * scale, 1),
            height: max(size.height * scale, 1)
        )
        var currentMaxDimension = min(maxPixelDimension, max(sourceSize.width, sourceSize.height))
        let qualities: [CGFloat] = [0.82, 0.72, 0.62, 0.52, 0.42, 0.34]

        repeat {
            let ratio = min(1, currentMaxDimension / max(sourceSize.width, sourceSize.height))
            let targetSize = CGSize(
                width: max((sourceSize.width * ratio).rounded(), 1),
                height: max((sourceSize.height * ratio).rounded(), 1)
            )
            let renderedImage = normalizedImage(pixelSize: targetSize)

            for quality in qualities {
                guard let data = renderedImage.jpegData(compressionQuality: quality) else { continue }
                if data.count <= maxByteCount {
                    return data
                }
            }

            currentMaxDimension *= 0.8
        } while currentMaxDimension >= 500

        return nil
    }

    private func normalizedImage(pixelSize: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: pixelSize, format: format)
        return renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: pixelSize))
            draw(in: CGRect(origin: .zero, size: pixelSize))
        }
    }
}
