import Foundation
import Testing
import UIKit
@testable import ArboreUi

struct CommunityTests {
    @Test func decodesCurrentBackendFeed() throws {
        let data = Data(
            """
            [{
              "id": "64b7abdecf2160b649ab6085",
              "userId": "user-1",
              "type": "before_after",
              "title": "Mon jardin",
              "description": "Trois mois plus tard",
              "imageUrl": "https://api.arbore.app/uploads/community/test.jpg",
              "likesCount": 3,
              "createdAt": "2026-07-14T12:34:56.123456789Z"
            }]
            """.utf8
        )

        let posts = try CommunityPayloadDecoder.decodeFeed(from: data)

        #expect(posts.count == 1)
        #expect(posts[0].id == "64b7abdecf2160b649ab6085")
        #expect(posts[0].type == .beforeAfter)
        #expect(posts[0].likesCount == 3)
    }

    @Test func decodesWrappedLegacyFeed() throws {
        let data = Data(
            """
            {"data":{"posts":[{
              "id": {"$oid": "64b7abdecf2160b649ab6086"},
              "userID": "user-2",
              "type": "dreamGarden",
              "title": "Projet terrasse",
              "description": "Une idée pour cet été",
              "imageURL": "https://api.arbore.app/uploads/community/legacy.jpg",
              "likes": "7",
              "created_at": 1784032496123
            }]}}
            """.utf8
        )

        let posts = try CommunityPayloadDecoder.decodeFeed(from: data)

        #expect(posts.count == 1)
        #expect(posts[0].id == "64b7abdecf2160b649ab6086")
        #expect(posts[0].userID == "user-2")
        #expect(posts[0].type == .dreamGarden)
        #expect(posts[0].likesCount == 7)
    }

    @Test func treatsNullFeedAsEmpty() throws {
        let posts = try CommunityPayloadDecoder.decodeFeed(from: Data("null".utf8))
        #expect(posts.isEmpty)
    }

    @Test func preparesCommunityImageBelowProxyLimit() throws {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: 2_400, height: 1_800),
            format: format
        )
        let image = renderer.image { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2_400, height: 1_800))
            UIColor.systemYellow.setFill()
            context.fill(CGRect(x: 300, y: 300, width: 1_800, height: 1_200))
        }

        let data = try #require(image.communityUploadJPEGData())

        #expect(data.count <= 850_000)
    }
}
