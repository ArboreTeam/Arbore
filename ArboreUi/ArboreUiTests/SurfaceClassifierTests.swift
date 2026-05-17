//
//  SurfaceClassifierTests.swift
//  ArboreUiTests
//
//  Couvre la classification heuristique non-LiDAR de SurfaceClassifier
//  (issue #186 Phase 1). Tests purs : on construit des PlaneFeatures
//  fictifs et on vérifie le verdict du classifier — pas d'ARKit nécessaire.
//

import XCTest
import simd
@testable import ArboreUi

final class SurfaceClassifierTests: XCTestCase {

    // MARK: - Fixtures

    private func horizontal(y: Float, width: Float = 2.0, depth: Float = 2.0,
                            x: Float = 0, z: Float = 0) -> PlaneFeatures {
        PlaneFeatures(
            alignment: .horizontal,
            center: SIMD3<Float>(x, y, z),
            extentWidth: width,
            extentDepth: depth,
            normal: SIMD3<Float>(0, 1, 0)
        )
    }

    private func vertical(at center: SIMD3<Float>,
                          width: Float = 3.0, height: Float = 2.5,
                          normal: SIMD3<Float> = SIMD3<Float>(1, 0, 0)) -> PlaneFeatures {
        PlaneFeatures(
            alignment: .vertical,
            center: center,
            extentWidth: width,
            extentDepth: height,
            normal: normal
        )
    }

    // MARK: - Trivial cases

    func test_vertical_isAlwaysWall() {
        let wall = vertical(at: SIMD3<Float>(2, 1.2, 0))
        XCTAssertEqual(
            SurfaceClassifier.classify(plane: wall, floorY: 0, cameraY: 1.6),
            .wall
        )
    }

    func test_horizontalAtFloorLevel_isFloor() {
        let floor = horizontal(y: 0)
        XCTAssertEqual(
            SurfaceClassifier.classify(plane: floor, floorY: 0, cameraY: 1.6),
            .floor
        )
    }

    func test_horizontalAtKnownFloorPlusTolerance_isFloor() {
        // Within 10cm of the floor level → still floor.
        let lowBump = horizontal(y: 0.08)
        XCTAssertEqual(
            SurfaceClassifier.classify(plane: lowBump, floorY: 0, cameraY: 1.6),
            .floor
        )
    }

    func test_horizontalAtFloorPlusMoreThanTolerance_isNotFloor() {
        let stepUp = horizontal(y: 0.20)
        XCTAssertNotEqual(
            SurfaceClassifier.classify(plane: stepUp, floorY: 0, cameraY: 1.6),
            .floor
        )
    }

    // MARK: - Ceiling

    func test_horizontalAboveCamera_isCeiling() {
        // Camera at 1.6m, ceiling at 2.4m → 0.8m above → ceiling.
        let ceiling = horizontal(y: 2.4)
        XCTAssertEqual(
            SurfaceClassifier.classify(plane: ceiling, floorY: 0, cameraY: 1.6),
            .ceiling
        )
    }

    func test_horizontalAtCameraHeight_isNotCeiling() {
        // Exactly at the camera level shouldn't be a ceiling — could be a
        // very tall table or a high shelf.
        let candidate = horizontal(y: 1.6, width: 0.4, depth: 0.4)
        let kind = SurfaceClassifier.classify(plane: candidate, floorY: 0, cameraY: 1.6)
        XCTAssertNotEqual(kind, .ceiling)
    }

    // MARK: - Shelf vs Table

    func test_smallElevatedHorizontal_isShelf() {
        // 60×40cm elevated to 1.2m → bookshelf.
        let shelf = horizontal(y: 1.2, width: 0.6, depth: 0.4, x: 5, z: 5)
        XCTAssertEqual(
            SurfaceClassifier.classify(plane: shelf, floorY: 0, cameraY: 1.6),
            .shelf
        )
    }

    func test_largeElevatedHorizontal_isTable() {
        // 1.6×1.0m elevated to 0.75m → dining table.
        let table = horizontal(y: 0.75, width: 1.6, depth: 1.0, x: 5, z: 5)
        XCTAssertEqual(
            SurfaceClassifier.classify(plane: table, floorY: 0, cameraY: 1.6),
            .table
        )
    }

    func test_shelfTableCutoffAt1m2() {
        // Exactly 1m² should pick `.table` (>= cutoff).
        let edgeCase = horizontal(y: 0.8, width: 1.0, depth: 1.0, x: 5, z: 5)
        XCTAssertEqual(
            SurfaceClassifier.classify(plane: edgeCase, floorY: 0, cameraY: 1.6),
            .table
        )
    }

    // MARK: - Floor inference when no reference yet

    func test_floorMissing_bestEffortIsFloor() {
        // First horizontal plane ever seen → best-effort label as floor.
        let candidate = horizontal(y: -0.3, width: 3, depth: 3)
        XCTAssertEqual(
            SurfaceClassifier.classify(plane: candidate, floorY: nil, cameraY: 1.6),
            .floor
        )
    }

    // MARK: - Windowsill detection

    func test_horizontalAdjacentToVertical_isWindowsill() {
        // 40×15cm rebord (longue et étroite) à 1m, accolé à un mur vertical
        // centré 30cm plus loin. La distance horizontale est petite par
        // rapport à l'extent du rebord → windowsill détecté.
        let rebord = horizontal(y: 1.0, width: 0.4, depth: 0.15, x: 1.5, z: 0)
        let wall = vertical(at: SIMD3<Float>(1.7, 1.2, 0))
        XCTAssertEqual(
            SurfaceClassifier.classify(plane: rebord, floorY: 0, cameraY: 1.6,
                                       nearbyVerticals: [wall]),
            .windowsill
        )
    }

    func test_horizontalFarFromVertical_isNotWindowsill() {
        // Une table au milieu d'une pièce — un mur existe mais à 3m.
        let table = horizontal(y: 0.75, width: 1.6, depth: 1.0, x: 0, z: 0)
        let wallFar = vertical(at: SIMD3<Float>(3.0, 1.2, 0))
        XCTAssertEqual(
            SurfaceClassifier.classify(plane: table, floorY: 0, cameraY: 1.6,
                                       nearbyVerticals: [wallFar]),
            .table
        )
    }

    func test_horizontalAdjacentToVerticalButOutsideWallHeight_isNotWindowsill() {
        // Surface horizontale collée à un mur, mais bien plus haut que le
        // sommet du mur (mur de 2.5m centré à 1.2m → top à ~2.45m). Une
        // plane à 4m est hors du mur → c'est probablement le plafond, pas
        // un windowsill.
        // Pour ce test on isole juste la règle adjacence, donc on garde Y
        // sous le ceiling-threshold mais hors de l'extent vertical du mur.
        let plane = horizontal(y: 3.0, width: 0.4, depth: 0.15, x: 1.5, z: 0)
        let wall = vertical(at: SIMD3<Float>(1.7, 1.2, 0)) // top à ~2.45m
        let kind = SurfaceClassifier.classify(plane: plane, floorY: 0, cameraY: 4.0,
                                              nearbyVerticals: [wall])
        XCTAssertNotEqual(kind, .windowsill)
    }
}
