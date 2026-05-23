//
//  MarchingCubesTests.swift
//  ArboreUiTests
//
//  Valide l'extraction de mesh marching cubes (#189) sur des champs
//  synthétiques : plan signé (devrait produire des triangles le long
//  de l'iso=0), tout-positif/tout-négatif (rien à extraire), et un
//  cas dégénéré edges-parfaits.
//

import XCTest
import simd
@testable import ArboreUi

final class MarchingCubesTests: XCTestCase {

    private typealias Key = TSDFGrid.Key
    private typealias Cell = TSDFGrid.Cell

    /// Build a Cell with a given TSDF value. Weight is hard-coded high
    /// enough to clear the default minWeight=3 filter in tests below.
    private func cell(tsdf: Float, category: Int8 = 0) -> Cell {
        return Cell(
            tsdf: tsdf,
            weight: 10,
            color: SIMD3<Float>(repeating: 0.5),
            votes: [category: 1],
            lastTouchedAt: 0
        )
    }

    // MARK: - Trivial cases

    func test_extractMesh_emptyGrid_yieldsEmptyMesh() {
        let mesh = MarchingCubes.extractMesh(cells: [:], voxelSize: 1.0)
        XCTAssertTrue(mesh.vertices.isEmpty)
        XCTAssertTrue(mesh.indices.isEmpty)
    }

    func test_extractMesh_allCornersPositive_yieldsNoTriangles() {
        // 2x2x2 cube where all corners have positive TSDF — outside the
        // surface, no iso-crossing.
        var cells: [Key: Cell] = [:]
        for x in 0...1 {
            for y in 0...1 {
                for z in 0...1 {
                    cells[Key(x: Int32(x), y: Int32(y), z: Int32(z))] = cell(tsdf: 0.5)
                }
            }
        }
        let mesh = MarchingCubes.extractMesh(cells: cells, voxelSize: 1.0)
        XCTAssertTrue(mesh.vertices.isEmpty)
    }

    func test_extractMesh_allCornersNegative_yieldsNoTriangles() {
        // All corners "inside" — also no iso-crossing.
        var cells: [Key: Cell] = [:]
        for x in 0...1 {
            for y in 0...1 {
                for z in 0...1 {
                    cells[Key(x: Int32(x), y: Int32(y), z: Int32(z))] = cell(tsdf: -0.5)
                }
            }
        }
        let mesh = MarchingCubes.extractMesh(cells: cells, voxelSize: 1.0)
        XCTAssertTrue(mesh.vertices.isEmpty)
    }

    // MARK: - Real iso-surface

    func test_extractMesh_singleCornerNegative_yieldsOneTriangle() {
        // Classic case 1 : corner v0 (at (0,0,0)) is inside, all 7
        // others are outside. Standard MC table emits a single
        // triangle spanning the three edges incident to v0.
        var cells: [Key: Cell] = [:]
        // 8 corners of a unit cube (cornerOffsets order in the LUT).
        let offsets: [(Int32, Int32, Int32)] = [
            (0,0,0), (1,0,0), (1,0,1), (0,0,1),
            (0,1,0), (1,1,0), (1,1,1), (0,1,1)
        ]
        for (i, o) in offsets.enumerated() {
            cells[Key(x: o.0, y: o.1, z: o.2)] = cell(tsdf: i == 0 ? -1.0 : 1.0)
        }
        let mesh = MarchingCubes.extractMesh(cells: cells, voxelSize: 1.0)
        XCTAssertEqual(mesh.vertices.count, 3)
        XCTAssertEqual(mesh.indices.count, 3)
        XCTAssertEqual(mesh.normals.count, 3)
    }

    func test_extractMesh_planeAlongY_producesAxisAlignedTriangles() {
        // Build a 3x3x3 voxel grid where TSDF = y - 1.5 (units of
        // half-voxels), so the iso-surface tsdf=0 is the plane y=1.5
        // (mid-way between y=1 and y=2). MC must produce a roughly
        // axis-aligned set of triangles cutting through the middle.
        var cells: [Key: Cell] = [:]
        for x in 0...2 {
            for y in 0...2 {
                for z in 0...2 {
                    // SDF = y - 1.5 → negative below y=1, positive above y=2.
                    let sdf = Float(y) - 1.5
                    cells[Key(x: Int32(x), y: Int32(y), z: Int32(z))] = cell(tsdf: sdf)
                }
            }
        }
        let mesh = MarchingCubes.extractMesh(cells: cells, voxelSize: 1.0)
        // We expect a non-empty mesh whose vertices are all clustered
        // around y=1.5 (the iso-plane).
        XCTAssertGreaterThan(mesh.vertices.count, 0)
        for v in mesh.vertices {
            // World position of voxel (0, 1, 0) centre is (0.5, 1.5, 0.5)
            // The interpolated iso surface for SDF=y-1.5 (samples at y=1 and y=2 with values -0.5, +0.5)
            // sits at y=1.5 in voxel-local space → world y=2.0 (since centre adds 0.5).
            // Allow ±0.05 tolerance for floating-point rounding.
            XCTAssertEqual(v.y, 2.0, accuracy: 0.05,
                           "Iso-surface vertex should sit on y=2.0")
        }
    }

    func test_extractMesh_respectsMinWeight() {
        // Same single-corner-inside case but with weight=1 (below the
        // default minWeight=3). MC must skip the cube entirely.
        var cells: [Key: Cell] = [:]
        let offsets: [(Int32, Int32, Int32)] = [
            (0,0,0), (1,0,0), (1,0,1), (0,0,1),
            (0,1,0), (1,1,0), (1,1,1), (0,1,1)
        ]
        for (i, o) in offsets.enumerated() {
            cells[Key(x: o.0, y: o.1, z: o.2)] = Cell(
                tsdf: i == 0 ? -1.0 : 1.0,
                weight: 1,   // below default minWeight=3
                color: SIMD3<Float>(repeating: 0.5),
                votes: [0: 1],
                lastTouchedAt: 0
            )
        }
        let mesh = MarchingCubes.extractMesh(cells: cells, voxelSize: 1.0)
        XCTAssertTrue(mesh.vertices.isEmpty,
                      "Low-weight corners should suppress the cube")
    }
}
