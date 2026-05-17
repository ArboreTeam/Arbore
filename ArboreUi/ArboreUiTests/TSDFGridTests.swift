//
//  TSDFGridTests.swift
//  ArboreUiTests
//
//  Couvre TSDFGrid (#189) : weighted-average SDF update, troncature,
//  vote majoritaire de catégorie hérité de VoxelGrid, et thread-safety.
//

import XCTest
import simd
@testable import ArboreUi

final class TSDFGridTests: XCTestCase {

    // MARK: - Integration math

    func test_integrate_storesObservationAsTruncatedTSDF() {
        let grid = TSDFGrid(voxelSize: 1.0, truncationDistance: 0.5)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)

        grid.integrate(key: key, sdf: 0.3, categoryIndex: 0, now: 1.0)
        let cell = grid.cell(at: key)
        XCTAssertNotNil(cell)
        XCTAssertEqual(cell?.tsdf ?? .nan, 0.3, accuracy: 1e-6)
        XCTAssertEqual(cell?.weight, Float(1))
    }

    func test_integrate_clampsBeyondTruncationDistance() {
        let grid = TSDFGrid(voxelSize: 1.0, truncationDistance: 0.5)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)

        // SDF=2 is well beyond the truncation — gets clamped to +0.5
        grid.integrate(key: key, sdf: 2.0, categoryIndex: 0, now: 1.0)
        XCTAssertEqual(grid.cell(at: key)?.tsdf ?? .nan, 0.5, accuracy: 1e-6)

        // Negative side also truncates.
        let key2 = TSDFGrid.Key(x: 1, y: 0, z: 0)
        grid.integrate(key: key2, sdf: -2.0, categoryIndex: 0, now: 1.0)
        XCTAssertEqual(grid.cell(at: key2)?.tsdf ?? .nan, -0.5, accuracy: 1e-6)
    }

    func test_integrate_weightedAverageOverMultipleObservations() {
        let grid = TSDFGrid(voxelSize: 1.0, truncationDistance: 1.0)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)

        // Three observations at 0.6, 0.4, 0.5. Weighted mean = 0.5.
        grid.integrate(key: key, sdf: 0.6, categoryIndex: 0, now: 1.0)
        grid.integrate(key: key, sdf: 0.4, categoryIndex: 0, now: 2.0)
        grid.integrate(key: key, sdf: 0.5, categoryIndex: 0, now: 3.0)

        let cell = grid.cell(at: key)!
        XCTAssertEqual(cell.weight, Float(3))
        XCTAssertEqual(cell.tsdf, Float(0.5), accuracy: 1e-6)
    }

    func test_integrate_isResistantToOneOutlier() {
        // Standard TSDF behaviour : a single bad sample doesn't ruin
        // the cell because subsequent good ones diminish its weight
        // contribution. Same as a running average.
        let grid = TSDFGrid(voxelSize: 1.0, truncationDistance: 1.0)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)

        // 9 clean observations at 0.0 + 1 outlier at 0.9.
        for _ in 0..<9 {
            grid.integrate(key: key, sdf: 0.0, categoryIndex: 0, now: 1.0)
        }
        grid.integrate(key: key, sdf: 0.9, categoryIndex: 0, now: 1.0)

        let cell = grid.cell(at: key)!
        XCTAssertEqual(cell.weight, Float(10))
        // Running average : 0.9 contributes 0.09 to the mean.
        XCTAssertEqual(cell.tsdf, Float(0.09), accuracy: 0.01)
    }

    func test_integrate_capsWeightAtMaxWeight() {
        let grid = TSDFGrid(voxelSize: 1.0, truncationDistance: 1.0, maxWeight: 5)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)
        for _ in 0..<20 {
            grid.integrate(key: key, sdf: 0.1, categoryIndex: 0, now: 1.0)
        }
        XCTAssertEqual(grid.cell(at: key)?.weight, Float(5))
    }

    // MARK: - Category votes

    func test_winningCategory_returnsMajorityVote() {
        let grid = TSDFGrid(voxelSize: 1.0, truncationDistance: 1.0)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)

        grid.integrate(key: key, sdf: 0, categoryIndex: 5, now: 1.0)
        grid.integrate(key: key, sdf: 0, categoryIndex: 3, now: 2.0)
        grid.integrate(key: key, sdf: 0, categoryIndex: 3, now: 3.0)
        grid.integrate(key: key, sdf: 0, categoryIndex: 3, now: 4.0)

        XCTAssertEqual(grid.cell(at: key)?.winningCategory, 3)
    }

    func test_integrate_acceptsNilCategoryWithoutCrashing() {
        let grid = TSDFGrid(voxelSize: 1.0)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)
        grid.integrate(key: key, sdf: 0.1, categoryIndex: nil, now: 1.0)
        let cell = grid.cell(at: key)!
        XCTAssertEqual(cell.weight, Float(1))
        XCTAssertNil(cell.winningCategory)
    }

    // MARK: - Snapshot & clear

    func test_snapshot_returnsIndependentCopy() {
        let grid = TSDFGrid(voxelSize: 1.0)
        let k = TSDFGrid.Key(x: 0, y: 0, z: 0)
        grid.integrate(key: k, sdf: 0, categoryIndex: 0, now: 1.0)
        let snap = grid.snapshot()
        grid.integrate(key: TSDFGrid.Key(x: 1, y: 0, z: 0), sdf: 0, categoryIndex: 0, now: 1.0)
        XCTAssertEqual(snap.count, 1)
        XCTAssertEqual(grid.count, 2)
    }

    func test_clear_dropsEverything() {
        let grid = TSDFGrid(voxelSize: 1.0)
        for i in 0..<5 {
            grid.integrate(key: TSDFGrid.Key(x: Int32(i), y: 0, z: 0),
                           sdf: 0, categoryIndex: 0, now: 1.0)
        }
        grid.clear()
        XCTAssertEqual(grid.count, 0)
    }

    // MARK: - Concurrency

    func test_concurrentIntegrate_isThreadSafe() async {
        let grid = TSDFGrid(voxelSize: 1.0)
        let writers = 8
        let perWriter = 50
        await withTaskGroup(of: Void.self) { group in
            for w in 0..<writers {
                group.addTask {
                    for i in 0..<perWriter {
                        let key = TSDFGrid.Key(x: Int32(w * perWriter + i), y: 0, z: 0)
                        grid.integrate(key: key, sdf: 0.0, categoryIndex: 0, now: 1.0)
                    }
                }
            }
            for _ in 0..<4 {
                group.addTask {
                    for _ in 0..<25 {
                        _ = grid.snapshot()
                    }
                }
            }
        }
        XCTAssertEqual(grid.count, writers * perWriter)
    }
}
