//
//  MeanValueCoordinatesTests.swift
//  ArboreUiTests
//
//  Couvre la math MVC qui sert au morphing de jardin (issue #173).
//

import XCTest
import simd
@testable import ArboreUi

final class MeanValueCoordinatesTests: XCTestCase {

    // MARK: - Fixtures

    /// Carré unité CCW (counter-clockwise) centré sur l'origine.
    private let unitSquareCCW: [SIMD2<Float>] = [
        SIMD2(-1, -1),  // bottom-left
        SIMD2( 1, -1),  // bottom-right
        SIMD2( 1,  1),  // top-right
        SIMD2(-1,  1),  // top-left
    ]

    /// Tolérance pour les comparaisons float — large car les calculs MVC
    /// passent par atan2/tan/division et accumulent du bruit numérique.
    private let eps: Float = 1e-4

    // MARK: - Sum-to-one invariant

    func test_weights_pointInside_normalizedToOne() {
        let p = SIMD2<Float>(0.2, 0.3)
        let weights = MeanValueCoordinates.weights(point: p, polygon: unitSquareCCW)
        let sum = weights.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: eps, "MVC weights must sum to 1")
        XCTAssertEqual(weights.count, unitSquareCCW.count)
    }

    func test_weights_pointAtCenter_uniformWeights() {
        let p = SIMD2<Float>(0, 0)
        let weights = MeanValueCoordinates.weights(point: p, polygon: unitSquareCCW)
        // Centre du carré → poids égaux 0.25 chacun.
        for w in weights {
            XCTAssertEqual(w, 0.25, accuracy: eps)
        }
    }

    // MARK: - Vertex / edge clamps

    func test_weights_pointAtVertex_oneHot() {
        let p = unitSquareCCW[2]  // top-right
        let weights = MeanValueCoordinates.weights(point: p, polygon: unitSquareCCW)
        // weight[2] must be 1, others 0.
        XCTAssertEqual(weights[0], 0, accuracy: eps)
        XCTAssertEqual(weights[1], 0, accuracy: eps)
        XCTAssertEqual(weights[2], 1, accuracy: eps)
        XCTAssertEqual(weights[3], 0, accuracy: eps)
    }

    func test_weights_pointOnEdgeMidpoint_linearBlend() {
        // Mid-point of bottom edge (between vertices 0 and 1) → 0.5/0.5.
        let p = SIMD2<Float>(0, -1)
        let weights = MeanValueCoordinates.weights(point: p, polygon: unitSquareCCW)
        XCTAssertEqual(weights[0], 0.5, accuracy: eps)
        XCTAssertEqual(weights[1], 0.5, accuracy: eps)
        XCTAssertEqual(weights[2], 0, accuracy: eps)
        XCTAssertEqual(weights[3], 0, accuracy: eps)
    }

    func test_weights_pointOnEdgeOffCenter_proportionalBlend() {
        // 1/4 from vertex 0, 3/4 from vertex 1.
        let p = SIMD2<Float>(-0.5, -1)
        let weights = MeanValueCoordinates.weights(point: p, polygon: unitSquareCCW)
        XCTAssertEqual(weights[0], 0.75, accuracy: eps)
        XCTAssertEqual(weights[1], 0.25, accuracy: eps)
    }

    // MARK: - Numerical stability near a vertex (F-3)

    func test_weights_pointNearVertex_stableFinite() {
        // Very close to a vertex but NOT exactly on it — exercise the
        // formerly-buggy code path where (1 - cos)/sin diverges. After the
        // atan2-based fix all weights remain finite and sum to 1.
        let p = unitSquareCCW[0] + SIMD2<Float>(1e-4, 1e-4)
        let weights = MeanValueCoordinates.weights(point: p, polygon: unitSquareCCW)
        for w in weights {
            XCTAssertTrue(w.isFinite, "weight should be finite near a vertex")
        }
        let sum = weights.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: eps)
    }

    // MARK: - Degenerate polygon fallback (F-5)

    func test_weights_collinearPolygon_uniformFallback() {
        // All vertices on the same line → totalWeight degenerates. The fix
        // returns uniform weights (1/n each) so apply() produces the
        // centroid, instead of an all-zeros vector that maps to (0, 0).
        let collinear: [SIMD2<Float>] = [
            SIMD2(0, 0),
            SIMD2(1, 0),
            SIMD2(2, 0),
            SIMD2(3, 0),
        ]
        let p = SIMD2<Float>(1.5, 1)
        let weights = MeanValueCoordinates.weights(point: p, polygon: collinear)
        let sum = weights.reduce(0, +)
        XCTAssertEqual(sum, 1.0, accuracy: eps, "fallback must still sum to 1")
        for w in weights {
            XCTAssertTrue(w.isFinite)
            XCTAssertGreaterThanOrEqual(w, 0)
        }
    }

    // MARK: - apply()

    func test_apply_identicalPolygon_returnsOriginalPoint() {
        let p = SIMD2<Float>(0.3, 0.7)
        let weights = MeanValueCoordinates.weights(point: p, polygon: unitSquareCCW)
        let recovered = MeanValueCoordinates.apply(weights: weights, to: unitSquareCCW)
        XCTAssertEqual(recovered.x, p.x, accuracy: eps)
        XCTAssertEqual(recovered.y, p.y, accuracy: eps)
    }

    func test_apply_scaledPolygon_scaledPoint() {
        let p = SIMD2<Float>(0.3, 0.5)
        let weights = MeanValueCoordinates.weights(point: p, polygon: unitSquareCCW)

        let scaledSquare = unitSquareCCW.map { $0 * 2 }
        let morphed = MeanValueCoordinates.apply(weights: weights, to: scaledSquare)

        XCTAssertEqual(morphed.x, p.x * 2, accuracy: eps)
        XCTAssertEqual(morphed.y, p.y * 2, accuracy: eps)
    }

    func test_apply_translatedPolygon_translatedPoint() {
        let p = SIMD2<Float>(0.0, 0.0)  // centre
        let weights = MeanValueCoordinates.weights(point: p, polygon: unitSquareCCW)

        let translatedSquare = unitSquareCCW.map { $0 + SIMD2<Float>(10, -5) }
        let morphed = MeanValueCoordinates.apply(weights: weights, to: translatedSquare)

        XCTAssertEqual(morphed.x, 10, accuracy: eps)
        XCTAssertEqual(morphed.y, -5, accuracy: eps)
    }

    // MARK: - Signed area (F-4 building block)

    func test_signedArea_ccwSquare_positive() {
        let area = MeanValueCoordinates.signedArea(unitSquareCCW)
        XCTAssertGreaterThan(area, 0, "CCW polygon must have positive signed area")
        XCTAssertEqual(area, 4, accuracy: eps, "unit square (-1..1)² has area 4")
    }

    func test_signedArea_cwSquare_negative() {
        let cw = Array(unitSquareCCW.reversed())
        let area = MeanValueCoordinates.signedArea(cw)
        XCTAssertLessThan(area, 0, "CW polygon must have negative signed area")
        XCTAssertEqual(abs(area), 4, accuracy: eps)
    }

    func test_signedArea_degeneratePolygon_zero() {
        let collinear: [SIMD2<Float>] = [SIMD2(0, 0), SIMD2(1, 0), SIMD2(2, 0)]
        XCTAssertEqual(MeanValueCoordinates.signedArea(collinear), 0, accuracy: eps)
    }
}
