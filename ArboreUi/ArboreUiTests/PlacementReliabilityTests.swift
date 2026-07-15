import XCTest
@testable import ArboreUi

final class PlacementReliabilityTests: XCTestCase {
    func testExistingGeometryIsPlaceableWithoutStabilityDelay() {
        let reliability = PlacementReliabilityScorer.evaluate(
            source: .existingPlaneGeometry,
            trackingNormal: true,
            surfaceAccepted: true,
            planeArea: 1.4,
            cameraDistance: 1.2,
            stableDuration: 0
        )

        XCTAssertEqual(reliability.reason, .ready)
        XCTAssertTrue(reliability.isPlaceable)
    }

    func testEstimatedPlaneNeedsShortStabilityBeforeCommit() {
        let early = PlacementReliabilityScorer.evaluate(
            source: .estimatedPlane,
            trackingNormal: true,
            surfaceAccepted: true,
            planeArea: 1.4,
            cameraDistance: 1.2,
            stableDuration: 0.12
        )
        XCTAssertEqual(early.reason, .unstableSurface)
        XCTAssertFalse(early.isPlaceable)

        let stable = PlacementReliabilityScorer.evaluate(
            source: .estimatedPlane,
            trackingNormal: true,
            surfaceAccepted: true,
            planeArea: 1.4,
            cameraDistance: 1.2,
            stableDuration: PlacementReliabilityScorer.fullStabilityDuration
        )
        XCTAssertEqual(stable.reason, .ready)
        XCTAssertTrue(stable.isPlaceable)
    }

    func testTrackingLimitedBlocksPlacement() {
        let reliability = PlacementReliabilityScorer.evaluate(
            source: .existingPlaneGeometry,
            trackingNormal: false,
            surfaceAccepted: true,
            planeArea: 2,
            cameraDistance: 1.0,
            stableDuration: 1
        )

        XCTAssertEqual(reliability.reason, .trackingLimited)
        XCTAssertFalse(reliability.isPlaceable)
    }

    func testIncompatibleSurfaceBlocksPlacement() {
        let reliability = PlacementReliabilityScorer.evaluate(
            source: .existingPlaneGeometry,
            trackingNormal: true,
            surfaceAccepted: false,
            planeArea: 2,
            cameraDistance: 1.0,
            stableDuration: 1
        )

        XCTAssertEqual(reliability.reason, .incompatibleSurface)
        XCTAssertFalse(reliability.isPlaceable)
    }
}
