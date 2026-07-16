import XCTest
@testable import ArboreUi

final class PerimeterTracingTests: XCTestCase {
    func testRectanglePlacedInDiagonalOrderBecomesValidBoundary() {
        let manager = GardenManager()

        XCTAssertTrue(manager.addPoint(SIMD3<Float>(0, 0, 0)))
        XCTAssertTrue(manager.addPoint(SIMD3<Float>(4, 0, 3)))
        XCTAssertTrue(manager.addPoint(SIMD3<Float>(4, 0, 0)))
        XCTAssertTrue(manager.addPoint(SIMD3<Float>(0, 0, 3)))

        XCTAssertEqual(manager.points.count, 4)
        XCTAssertEqual(manager.area, 12, accuracy: 0.001)
        XCTAssertEqual(manager.perimeter, 14, accuracy: 0.001)
    }

    func testPointTooCloseToExistingPointIsRejected() {
        let manager = GardenManager()

        XCTAssertTrue(manager.addPoint(SIMD3<Float>(0, 0, 0)))
        XCTAssertFalse(manager.addPoint(SIMD3<Float>(0.05, 0, 0.04)))

        XCTAssertEqual(manager.points.count, 1)
    }

    func testUndoRemovesMostRecentlyPlacedPointAfterAutomaticOrdering() {
        let manager = GardenManager()
        manager.addPoint(SIMD3<Float>(0, 0, 0))
        manager.addPoint(SIMD3<Float>(4, 0, 3))
        manager.addPoint(SIMD3<Float>(4, 0, 0))
        manager.addPoint(SIMD3<Float>(0, 0, 3))

        manager.undoLastPoint()

        XCTAssertEqual(manager.points.count, 3)
        XCTAssertFalse(manager.points.contains(SIMD3<Float>(0, 0, 3)))
        XCTAssertEqual(manager.area, 6, accuracy: 0.001)
    }
}
