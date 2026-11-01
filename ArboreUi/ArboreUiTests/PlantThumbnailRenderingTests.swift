import XCTest
import UIKit
@testable import ArboreUi

// Ce qui reste ici est le CONSOMMATEUR de vignettes : l'URL distante et le
// détecteur d'ancienneté. L'app ne rend plus de vignettes (#696), donc les deux
// tests de `PlantThumbnailFraming.fit` sont partis avec le renderer.
//
// Le cadrage n'est pas pour autant sans test : il a été porté littéralement
// dans `vignettes/rendre.py`, et c'est là qu'il est désormais éprouvé — sur le
// rendu réel, par les quatre contrôles de `controler()`, qui sont exactement
// ceux que `isLegacyThumbnail` applique ci-dessous. Un cadrage faux ne produit
// plus un nombre qui diffère, il produit une vignette que l'app refuse.
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
