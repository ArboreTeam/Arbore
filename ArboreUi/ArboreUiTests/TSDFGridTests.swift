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

    // MARK: - Weight-aware integration (#189 follow-up B v2)

    func test_freeSpaceObservations_pullCellTowardEmpty() {
        // Sanity check : equally-weighted observations average linearly.
        let grid = TSDFGrid(voxelSize: 1.0, truncationDistance: 0.5, maxWeight: 100)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)
        grid.integrate(key: key, sdf: 0.0, categoryIndex: 0, now: 1.0)
        for _ in 0..<20 {
            grid.integrate(key: key, sdf: 1.0, categoryIndex: 0, now: 1.0)
        }
        let final = grid.cell(at: key)!.tsdf
        XCTAssertGreaterThan(final, 0.25,
                             "Free-space observations pull the cell out of the iso-surface")
    }

    func test_lowWeightCarve_doesNotOverpowerHighWeightSurface() {
        // Real surface seen 5 times with weight=1, then "carved" 5
        // times with weight=0.3 (noisy neighbour ray classifying it
        // as free space). Surface should still win the running average.
        let grid = TSDFGrid(voxelSize: 1.0, truncationDistance: 0.5, maxWeight: 100)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)
        for _ in 0..<5 {
            grid.integrate(key: key, sdf: 0.0, weight: 1.0, categoryIndex: 0, now: 1.0)
        }
        for _ in 0..<5 {
            grid.integrate(key: key, sdf: 0.5, weight: 0.3, categoryIndex: nil, now: 1.0)
        }
        let final = grid.cell(at: key)!.tsdf
        // Mean = (5·0 + 5·0.3·0.5) / (5 + 5·0.3) = 0.75/6.5 ≈ 0.115
        XCTAssertLessThan(final, 0.2,
                          "5 carves × weight 0.3 must NOT erase 5 surface observations")
    }

    func test_lowWeightCarve_doesEraseGhostWithFewSurfaceObs() {
        // Ghost voxel : 1 wrong on-surface observation (weight 1),
        // then many carves at weight 0.3 from new viewpoints.
        // After enough carves, the ghost should leave the iso-surface.
        let grid = TSDFGrid(voxelSize: 1.0, truncationDistance: 0.5, maxWeight: 100)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)
        grid.integrate(key: key, sdf: 0.0, weight: 1.0, categoryIndex: 0, now: 1.0)
        for _ in 0..<20 {
            grid.integrate(key: key, sdf: 0.5, weight: 0.3, categoryIndex: nil, now: 1.0)
        }
        let final = grid.cell(at: key)!.tsdf
        // Mean = (1·0 + 20·0.3·0.5) / (1 + 6) = 3/7 ≈ 0.43
        XCTAssertGreaterThan(final, 0.3,
                             "20 weighted carves should drag the ghost out of the iso-surface")
    }

    func test_integrate_zeroWeightIsNoOp() {
        let grid = TSDFGrid(voxelSize: 1.0)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)
        grid.integrate(key: key, sdf: 0.5, weight: 0.0, categoryIndex: 0, now: 1.0)
        XCTAssertNil(grid.cell(at: key))
    }

    // MARK: - Color accumulation (#189 follow-up C)

    func test_integrate_storesColorOnNewCell() {
        let grid = TSDFGrid(voxelSize: 1.0)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)
        let red = SIMD3<Float>(0.9, 0.1, 0.1)
        grid.integrate(key: key, sdf: 0, weight: 1.0, color: red,
                       categoryIndex: 0, now: 1.0)
        let stored = grid.cell(at: key)!.color
        XCTAssertEqual(stored.x, red.x, accuracy: 1e-5)
        XCTAssertEqual(stored.y, red.y, accuracy: 1e-5)
        XCTAssertEqual(stored.z, red.z, accuracy: 1e-5)
    }

    func test_integrate_averagesColorAcrossObservations() {
        // 3 obs : pure red, pure green, pure blue with equal weight.
        // Mean = (1/3, 1/3, 1/3).
        let grid = TSDFGrid(voxelSize: 1.0)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)
        grid.integrate(key: key, sdf: 0, weight: 1.0,
                       color: SIMD3<Float>(1, 0, 0), categoryIndex: 0, now: 1.0)
        grid.integrate(key: key, sdf: 0, weight: 1.0,
                       color: SIMD3<Float>(0, 1, 0), categoryIndex: 0, now: 1.0)
        grid.integrate(key: key, sdf: 0, weight: 1.0,
                       color: SIMD3<Float>(0, 0, 1), categoryIndex: 0, now: 1.0)
        let stored = grid.cell(at: key)!.color
        XCTAssertEqual(stored.x, 1.0/3.0, accuracy: 1e-5)
        XCTAssertEqual(stored.y, 1.0/3.0, accuracy: 1e-5)
        XCTAssertEqual(stored.z, 1.0/3.0, accuracy: 1e-5)
    }

    func test_integrate_nilColorLeavesExistingColorUntouched() {
        // First obs sets the colour, second obs passes nil (e.g. a
        // carve observation in the integrator). Stored colour must
        // still be the first one.
        let grid = TSDFGrid(voxelSize: 1.0)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)
        let teal = SIMD3<Float>(0.2, 0.8, 0.7)
        grid.integrate(key: key, sdf: 0, weight: 1.0, color: teal,
                       categoryIndex: 0, now: 1.0)
        grid.integrate(key: key, sdf: 0, weight: 1.0, color: nil,
                       categoryIndex: 0, now: 2.0)
        let stored = grid.cell(at: key)!.color
        XCTAssertEqual(stored.x, teal.x, accuracy: 1e-5)
        XCTAssertEqual(stored.y, teal.y, accuracy: 1e-5)
        XCTAssertEqual(stored.z, teal.z, accuracy: 1e-5)
    }

    func test_integrate_nilColorOnNewCellSeedsNeutralGray() {
        // Integrator may seed a cell with nil colour (e.g. legacy
        // callers / test paths without a captured image). The cell
        // must still construct cleanly — we seed neutral grey so
        // subsequent colour-bearing obs converge from the middle of
        // the cube rather than from black.
        let grid = TSDFGrid(voxelSize: 1.0)
        let key = TSDFGrid.Key(x: 0, y: 0, z: 0)
        grid.integrate(key: key, sdf: 0, weight: 1.0, color: nil,
                       categoryIndex: 0, now: 1.0)
        let stored = grid.cell(at: key)!.color
        XCTAssertEqual(stored.x, 0.5, accuracy: 1e-5)
        XCTAssertEqual(stored.y, 0.5, accuracy: 1e-5)
        XCTAssertEqual(stored.z, 0.5, accuracy: 1e-5)
    }


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
