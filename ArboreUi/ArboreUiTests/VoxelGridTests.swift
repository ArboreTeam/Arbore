//
//  VoxelGridTests.swift
//  ArboreUiTests
//
//  Couvre VoxelGrid réécrit après l'audit Phase 3 (issue #188) :
//   - thread-safety via lock interne (P0.1)
//   - FIFO O(1) avec ring head + compactage (P1.2)
//   - snapshot() pour la lecture atomique côté SceneKit
//

import XCTest
import simd
@testable import ArboreUi

final class VoxelGridTests: XCTestCase {

    // MARK: - Insert + lookup

    func test_insert_intoEmptyGrid_returnsTrueAndStores() {
        let grid = VoxelGrid(voxelSize: 0.04)
        let created = grid.insert(point: SIMD3<Float>(0, 0, 0),
                                  color: SIMD3<Float>(1, 0, 0),
                                  now: 1.0)
        XCTAssertTrue(created)
        XCTAssertEqual(grid.count, 1)
    }

    func test_insert_samePoint_returnsFalseAndKeepsSingleCell() {
        let grid = VoxelGrid(voxelSize: 0.04)
        _ = grid.insert(point: SIMD3<Float>(0.01, 0.01, 0.01),
                        color: SIMD3<Float>(1, 0, 0),
                        now: 1.0)
        let secondCreated = grid.insert(point: SIMD3<Float>(0.02, 0.02, 0.02),
                                        color: SIMD3<Float>(0, 1, 0),
                                        now: 2.0)
        // Both points are inside the same 0.04m voxel.
        XCTAssertFalse(secondCreated, "Second insert in same cell must return false")
        XCTAssertEqual(grid.count, 1)
    }

    func test_insert_nearbyButDifferentCells_createsTwoVoxels() {
        let grid = VoxelGrid(voxelSize: 0.04)
        _ = grid.insert(point: SIMD3<Float>(0, 0, 0), color: .zero, now: 1.0)
        _ = grid.insert(point: SIMD3<Float>(0.05, 0, 0), color: .zero, now: 1.0)
        XCTAssertEqual(grid.count, 2)
    }

    func test_quantize_negativeCoordinates_snapsCorrectly() {
        let grid = VoxelGrid(voxelSize: 0.04)
        // -0.01 and 0.01 should land in DIFFERENT cells because of the
        // floor() convention — anything <0 maps to a cell with x = -1.
        _ = grid.insert(point: SIMD3<Float>(-0.01, 0, 0), color: .zero, now: 1.0)
        _ = grid.insert(point: SIMD3<Float>(0.01, 0, 0), color: .zero, now: 1.0)
        XCTAssertEqual(grid.count, 2)
    }

    // MARK: - Snapshot

    func test_snapshot_returnsIndependentCopy() {
        let grid = VoxelGrid(voxelSize: 0.04)
        _ = grid.insert(point: SIMD3<Float>(0, 0, 0), color: .zero, now: 1.0)
        let snap1 = grid.snapshot()
        _ = grid.insert(point: SIMD3<Float>(1, 0, 0), color: .zero, now: 1.0)
        // Snapshot must not see the second insert.
        XCTAssertEqual(snap1.count, 1)
        XCTAssertEqual(grid.snapshot().count, 2)
    }

    // MARK: - FIFO eviction

    func test_eviction_dropsOldestPastCap() {
        let grid = VoxelGrid(voxelSize: 1.0, maxVoxels: 3)
        // 4 distinct cells inserted → first one must be evicted.
        _ = grid.insert(point: SIMD3<Float>(0, 0, 0), color: .zero, now: 1.0)
        _ = grid.insert(point: SIMD3<Float>(1, 0, 0), color: .zero, now: 2.0)
        _ = grid.insert(point: SIMD3<Float>(2, 0, 0), color: .zero, now: 3.0)
        _ = grid.insert(point: SIMD3<Float>(3, 0, 0), color: .zero, now: 4.0)
        XCTAssertEqual(grid.count, 3)
        // The (0,0,0) cell should have been evicted.
        let cells = grid.snapshot()
        XCTAssertNil(cells[VoxelGrid.Key(x: 0, y: 0, z: 0)])
        XCTAssertNotNil(cells[VoxelGrid.Key(x: 3, y: 0, z: 0)])
    }

    func test_eviction_skipsTombstones() {
        // Insert P1, then update P1 (same cell, no new order entry),
        // then fill past cap. The eviction must not crash trying to
        // remove an already-replaced key and must instead skip ahead.
        let grid = VoxelGrid(voxelSize: 1.0, maxVoxels: 2)
        _ = grid.insert(point: SIMD3<Float>(0, 0, 0), color: .zero, now: 1.0)
        _ = grid.insert(point: SIMD3<Float>(0, 0, 0), color: .zero, now: 2.0) // update
        _ = grid.insert(point: SIMD3<Float>(1, 0, 0), color: .zero, now: 3.0)
        _ = grid.insert(point: SIMD3<Float>(2, 0, 0), color: .zero, now: 4.0)
        XCTAssertEqual(grid.count, 2)
    }

    // MARK: - Clear

    func test_clear_dropsEverythingAndResetsRingHead() {
        let grid = VoxelGrid(voxelSize: 1.0, maxVoxels: 100)
        for i in 0..<10 {
            _ = grid.insert(point: SIMD3<Float>(Float(i), 0, 0),
                            color: .zero, now: TimeInterval(i))
        }
        XCTAssertEqual(grid.count, 10)
        grid.clear()
        XCTAssertEqual(grid.count, 0)
        XCTAssertEqual(grid.snapshot().count, 0)
        // After clear we can still insert without weirdness from a
        // stale ring head.
        _ = grid.insert(point: .zero, color: .zero, now: 1)
        XCTAssertEqual(grid.count, 1)
    }

    // MARK: - World centre

    func test_worldCenter_isHalfVoxelOffset() {
        let grid = VoxelGrid(voxelSize: 0.04)
        let key = VoxelGrid.Key(x: 0, y: 0, z: 0)
        let centre = grid.worldCenter(of: key)
        XCTAssertEqual(centre.x, 0.02, accuracy: 1e-6)
        XCTAssertEqual(centre.y, 0.02, accuracy: 1e-6)
        XCTAssertEqual(centre.z, 0.02, accuracy: 1e-6)
    }

    // MARK: - Concurrency

    /// 10 writer tasks hammering the grid in parallel with 10 reader
    /// tasks taking snapshots. Validates that the lock prevents the
    /// Dictionary data race (would crash under TSan otherwise) and
    /// that the final count is what we wrote.
    func test_concurrentInsertsAndSnapshots_areThreadSafe() async {
        let grid = VoxelGrid(voxelSize: 1.0, maxVoxels: 10_000)
        let writers = 10
        let perWriter = 100

        await withTaskGroup(of: Void.self) { group in
            for w in 0..<writers {
                group.addTask {
                    for i in 0..<perWriter {
                        let p = SIMD3<Float>(Float(w * perWriter + i), 0, 0)
                        _ = grid.insert(point: p, color: .zero, now: 1.0)
                    }
                }
            }
            for _ in 0..<10 {
                group.addTask {
                    for _ in 0..<50 {
                        _ = grid.snapshot()
                    }
                }
            }
        }
        XCTAssertEqual(grid.count, writers * perWriter)
    }
}
