import Foundation
import UIKit

@MainActor
final class CommunityViewModel: ObservableObject {
    @Published private(set) var posts: [CommunityPost] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isUploading = false
    @Published var errorMessage: String?

    private let api: CommunityAPI

    init(api: CommunityAPI = .shared) {
        self.api = api
    }

    func fetchFeed() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil

        do {
            posts = try await api.fetchFeed()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func uploadPost(
        title: String,
        description: String,
        type: CommunityPostType,
        image: UIImage
    ) async -> Bool {
        guard !isUploading else { return false }

        isUploading = true
        errorMessage = nil

        do {
            let createdPost = try await api.uploadPost(
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                type: type,
                image: image
            )
            posts.removeAll { $0.id == createdPost.id }
            posts.insert(createdPost, at: 0)
            isUploading = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            isUploading = false
            return false
        }
    }
}
