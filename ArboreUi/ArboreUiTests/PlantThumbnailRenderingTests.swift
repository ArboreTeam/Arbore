import XCTest
import UIKit
@testable import ArboreUi

final class PlantThumbnailRenderingTests: XCTestCase {
    func testRemoteThumbnailURLIncludesDesignVersionToBypassCDNCache() throws {
        let url = try XCTUnwrap(
            PlantThumbnailCache.remoteURL(
                for: "monstera_01",
                baseURL: "https://api.arbore.app"
            )
        )
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(url.path, "/models/thumbnails/monstera_01.png")
        XCTAssertEqual(
            components.queryItems,
            [URLQueryItem(name: "v", value: PlantThumbnailCache.version)]
        )
    }

    func testFramingMovesCameraBackForWidePlant() {
        let narrow = PlantThumbnailFraming.fit(
            width: 0.5,
            height: 1.5,
            depth: 0.4,
            aspectRatio: 0.8
        )
        let wide = PlantThumbnailFraming.fit(
            width: 2.5,
            height: 1.5,
            depth: 0.4,
            aspectRatio: 0.8
        )

        XCTAssertGreaterThan(wide.cameraDistance, narrow.cameraDistance)
    }

    func testFramingIncludesDepthWhenCameraIsPitched() {
        let shallow = PlantThumbnailFraming.fit(
            width: 1,
            height: 1,
            depth: 0.2,
            aspectRatio: 0.8
        )
        let deep = PlantThumbnailFraming.fit(
            width: 1,
            height: 1,
            depth: 2,
            aspectRatio: 0.8
        )

        XCTAssertGreaterThan(deep.cameraDistance, shallow.cameraDistance)
        XCTAssertEqual(deep.lookAtY, 0.5, accuracy: 0.0001)
    }

    func testLegacyDetectorRejectsPaleTopStrip() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 200, height: 250),
            format: format
        ).image { context in
            UIColor(white: 0.72, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 250))
            UIColor(white: 0.88, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 34))
        }

        let signedImage = PlantThumbnailCache.applyingCurrentDesignMarker(to: image)
        XCTAssertTrue(PlantThumbnailCache.isLegacyThumbnail(signedImage))
    }

    func testLegacyDetectorKeepsUniformStudioBackground() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 200, height: 250),
            format: format
        ).image { context in
            UIColor(white: 0.72, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 250))
        }

        let signedImage = PlantThumbnailCache.applyingCurrentDesignMarker(to: image)
        XCTAssertFalse(PlantThumbnailCache.isLegacyThumbnail(signedImage))
    }

    func testLegacyDetectorRejectsThumbnailWithoutCurrentDesignMarker() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 200, height: 250),
            format: format
        ).image { context in
            UIColor(white: 0.72, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 250))
        }

        XCTAssertFalse(PlantThumbnailCache.hasCurrentDesignMarker(image))
        XCTAssertTrue(PlantThumbnailCache.isLegacyThumbnail(image))
    }
}
