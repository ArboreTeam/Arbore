//
//  GardenMorpherTests.swift
//  ArboreUiTests
//
//  Couvre l'orchestration math du moteur de morphing (issue #173).
//  Math pure — n'instancie aucun nœud SceneKit, ne dépend pas d'ARKit.
//

import XCTest
import simd
@testable import ArboreUi

final class GardenMorpherTests: XCTestCase {

    private let eps: Float = 1e-3

    // MARK: - Helpers

    private func makePlant(x: Float, y: Float, z: Float) -> PersistedPlant {
        // Transform et position pointent vers le même point monde (convention
        // world-frame de l'issue #170). rotation/scale: identité.
        let identityScale: [Float] = [1, 1, 1]
        let identityRot:   [Float] = [0, 0, 0]
        let transform: [Float] = [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            x, y, z, 1,
        ]
        return PersistedPlant(
            plantID: "plant-\(x)-\(z)",
            plantName: "Test Plant",
            modelURLString: "test.usdz",
            position: [x, y, z],
            rotation: identityRot,
            scale: identityScale,
            transform: transform,
            upAxis: nil,
            surfaceType: "floor",
            surfaceHeight: y
        )
    }

    private func square(scale: Float = 1, center: SIMD3<Float> = .zero, y: Float = 0) -> [SIMD3<Float>] {
        return [
            center + SIMD3(-scale, y, -scale),
            center + SIMD3( scale, y, -scale),
            center + SIMD3( scale, y,  scale),
            center + SIMD3(-scale, y,  scale),
        ]
    }

    private func translation(of result: MorphedPlant) -> SIMD3<Float> {
        // Column 3 du transform = (tx, ty, tz, 1).
        return SIMD3(
            result.newTransform.columns.3.x,
            result.newTransform.columns.3.y,
            result.newTransform.columns.3.z
        )
    }

    // MARK: - Identity

    func test_morph_squareToSquare_positionsUnchanged() {
        let plants = [
            makePlant(x: 0.3, y: 0, z: -0.2),
            makePlant(x: -0.5, y: 0, z: 0.4),
        ]
        let boundary = square()
        let result = GardenMorpher.morph(
            oldPlants: plants,
            oldBoundary: boundary,
            newBoundary: boundary
        )
        XCTAssertEqual(result.morphedPlants.count, 2)
        for (mp, original) in zip(result.morphedPlants, plants) {
            let t = translation(of: mp)
            XCTAssertEqual(t.x, original.position[0], accuracy: eps)
            XCTAssertEqual(t.z, original.position[2], accuracy: eps)
        }
    }

    // MARK: - Scale-up

    func test_morph_squareToBiggerSquare_positionsScale() {
        let plant = makePlant(x: 0.4, y: 0, z: -0.3)
        let old = square(scale: 1)
        let new = square(scale: 3)  // × 3 around origin

        let result = GardenMorpher.morph(
            oldPlants: [plant],
            oldBoundary: old,
            newBoundary: new
        )
        let t = translation(of: result.morphedPlants[0])
        XCTAssertEqual(t.x, plant.position[0] * 3, accuracy: eps)
        XCTAssertEqual(t.z, plant.position[2] * 3, accuracy: eps)
    }

    // MARK: - Translation only

    func test_morph_squareToTranslatedSquare_positionsTranslated() {
        let plant = makePlant(x: 0.2, y: 0, z: 0.1)
        let old = square()
        let offset = SIMD3<Float>(5, 0, -2)
        let new = square().map { $0 + offset }

        let result = GardenMorpher.morph(
            oldPlants: [plant],
            oldBoundary: old,
            newBoundary: new
        )
        let t = translation(of: result.morphedPlants[0])
        XCTAssertEqual(t.x, plant.position[0] + offset.x, accuracy: eps)
        XCTAssertEqual(t.z, plant.position[2] + offset.z, accuracy: eps)
    }

    // MARK: - Floor delta (Y handling)

    func test_morph_newBoundaryHigherFloor_plantsLiftedByDelta() {
        let plant = makePlant(x: 0, y: 0, z: 0)
        let old = square(y: 0)
        let new = square(y: 0.5)  // floor moved up 50 cm

        let result = GardenMorpher.morph(
            oldPlants: [plant],
            oldBoundary: old,
            newBoundary: new
        )
        let t = translation(of: result.morphedPlants[0])
        XCTAssertEqual(t.y, 0.5, accuracy: eps)
    }

    func test_morph_floorYParameterOverridesAverage() {
        let plant = makePlant(x: 0, y: 0, z: 0)
        let old = square(y: 0)
        let new = square(y: 0.5)

        let result = GardenMorpher.morph(
            oldPlants: [plant],
            oldBoundary: old,
            newBoundary: new,
            floorY: 0.2
        )
        let t = translation(of: result.morphedPlants[0])
        // floorDelta = 0.2 - 0 = 0.2 → newY = oldY + 0.2 = 0.2
        XCTAssertEqual(t.y, 0.2, accuracy: eps)
    }

    // MARK: - Winding sign normalization (F-4)

    func test_morph_oppositeWinding_pointsStayInPlace() {
        let plant = makePlant(x: 0.5, y: 0, z: 0)
        let oldCCW = square()
        let newCW = Array(oldCCW.reversed())  // exact same shape, reverse order

        let result = GardenMorpher.morph(
            oldPlants: [plant],
            oldBoundary: oldCCW,
            newBoundary: newCW
        )
        let t = translation(of: result.morphedPlants[0])
        // Le shape est identique en géométrie, seul le winding change. Après
        // normalisation, la plante doit retomber sur sa position d'origine.
        XCTAssertEqual(t.x, plant.position[0], accuracy: eps)
        XCTAssertEqual(t.z, plant.position[2], accuracy: eps)
    }

    // MARK: - Out-of-polygon snap

    func test_morph_outsideOfNewPolygon_snappedToBoundary() {
        // Old polygon contains a point near edge ; new polygon is shrunk such
        // that the morphed point falls outside. The morpher must snap to the
        // closest edge instead of placing the plant in a void.
        let plant = makePlant(x: 0.9, y: 0, z: 0)
        let oldBig = square(scale: 1)
        let newSmall = square(scale: 0.3)  // shrunk → 0.9 maps outside

        let result = GardenMorpher.morph(
            oldPlants: [plant],
            oldBoundary: oldBig,
            newBoundary: newSmall
        )
        let t = translation(of: result.morphedPlants[0])
        // Le point doit être sur ou à l'intérieur du nouveau carré (±eps).
        let inside = abs(t.x) <= 0.3 + eps && abs(t.z) <= 0.3 + eps
        XCTAssertTrue(inside, "morphed point must be inside the new polygon, got (\(t.x), \(t.z))")
    }

    // MARK: - Fallback path (mismatched vertex counts)

    func test_morph_mismatchedVertexCount_fallbackProducesResult() {
        let plant = makePlant(x: 0.2, y: 0, z: 0.2)
        let oldSquare = square()
        let newTriangle: [SIMD3<Float>] = [
            SIMD3(-1, 0, -1),
            SIMD3( 1, 0, -1),
            SIMD3( 0, 0,  1),
        ]
        let result = GardenMorpher.morph(
            oldPlants: [plant],
            oldBoundary: oldSquare,
            newBoundary: newTriangle
        )
        // Fallback : la plante doit avoir un placement (pas vide) et un warning.
        XCTAssertEqual(result.morphedPlants.count, 1)
        XCTAssertNotNil(result.morphedPlants[0].warning)
        XCTAssertEqual(result.morphedPlants[0].warning?.severity, .severe)
    }

    // MARK: - Empty inputs

    func test_morph_noPlants_returnsEmpty() {
        let result = GardenMorpher.morph(
            oldPlants: [],
            oldBoundary: square(),
            newBoundary: square()
        )
        XCTAssertTrue(result.morphedPlants.isEmpty)
        XCTAssertTrue(result.warnings.isEmpty)
    }

    // MARK: - Performance smoke

    func test_morph_141plants_under1000ms() {
        // Sanity perf : 141 plantes (taille max plausible d'un gros jardin)
        // morphées sous le seuil de 1 seconde sur Mac (10× la cible iPhone).
        // Empêche une régression algo type O(n²) qui rendrait l'opération
        // visiblement lente à l'écran.
        var plants: [PersistedPlant] = []
        plants.reserveCapacity(141)
        for i in 0..<141 {
            let angle = Float(i) / 141 * 2 * .pi
            plants.append(makePlant(x: 0.5 * cos(angle), y: 0, z: 0.5 * sin(angle)))
        }
        measure {
            _ = GardenMorpher.morph(
                oldPlants: plants,
                oldBoundary: square(),
                newBoundary: square(scale: 2)
            )
        }
    }
}
