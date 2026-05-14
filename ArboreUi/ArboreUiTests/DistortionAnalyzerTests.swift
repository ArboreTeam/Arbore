//
//  DistortionAnalyzerTests.swift
//  ArboreUiTests
//
//  Couvre le scoring de distorsion utilisé pour signaler à l'utilisateur
//  quelles plantes risquent de se retrouver à une mauvaise position après
//  morphing (issue #173).
//

import XCTest
import simd
@testable import ArboreUi

final class DistortionAnalyzerTests: XCTestCase {

    private let unitSquare: [SIMD2<Float>] = [
        SIMD2(-1, -1),
        SIMD2( 1, -1),
        SIMD2( 1,  1),
        SIMD2(-1,  1),
    ]

    private let eps: Float = 1e-4

    // MARK: - Identity

    func test_score_identicalBoundaries_returnsOne() {
        let p = SIMD2<Float>(0.3, 0.4)
        let score = DistortionAnalyzer.score(
            oldPosition: p,
            newPosition: p,
            oldBoundary: unitSquare,
            newBoundary: unitSquare
        )
        XCTAssertEqual(score, 1.0, accuracy: eps)
    }

    // MARK: - Scale equivariance

    func test_score_uniformScaling_preserved() {
        let p = SIMD2<Float>(0.3, 0.4)
        let scaledSquare = unitSquare.map { $0 * 3 }
        let scaledP = p * 3

        let score = DistortionAnalyzer.score(
            oldPosition: p,
            newPosition: scaledP,
            oldBoundary: unitSquare,
            newBoundary: scaledSquare
        )
        // Le scoring est scale-invariant car newAvg = 3 * oldAvg, ratio = 3.
        // max(3, 1/3) = 3 → la distorsion s'exprime bien comme un facteur.
        XCTAssertEqual(score, 3.0, accuracy: eps)
    }

    // MARK: - Severity buckets

    func test_severity_thresholds() {
        XCTAssertEqual(DistortionAnalyzer.severity(for: 1.0),  .ok)
        XCTAssertEqual(DistortionAnalyzer.severity(for: 1.19), .ok)
        XCTAssertEqual(DistortionAnalyzer.severity(for: 1.2),  .moderate)
        XCTAssertEqual(DistortionAnalyzer.severity(for: 1.7),  .moderate)
        XCTAssertEqual(DistortionAnalyzer.severity(for: 1.8),  .severe)
        XCTAssertEqual(DistortionAnalyzer.severity(for: 5.0),  .severe)
    }

    // MARK: - Compression vs expansion symmetry

    func test_score_compressionAndExpansion_returnSameScore() {
        let p = SIMD2<Float>(0.5, 0)
        let big = unitSquare.map { $0 * 2 }
        let small = unitSquare.map { $0 * 0.5 }

        // Both: boundary 2× then 0.5×. Position keeps the same relative.
        let scoreUp = DistortionAnalyzer.score(
            oldPosition: p,
            newPosition: p * 2,
            oldBoundary: unitSquare,
            newBoundary: big
        )
        let scoreDown = DistortionAnalyzer.score(
            oldPosition: p,
            newPosition: p * 0.5,
            oldBoundary: unitSquare,
            newBoundary: small
        )
        // Le ratio est différent (2× vs 0.5×) mais le symmetric max(r, 1/r)
        // renvoie 2.0 dans les deux cas.
        XCTAssertEqual(scoreUp, scoreDown, accuracy: eps)
        XCTAssertEqual(scoreUp, 2.0, accuracy: eps)
    }

    // MARK: - cardinalZone

    func test_cardinalZone_centre() {
        let zone = DistortionAnalyzer.cardinalZone(
            of: SIMD2<Float>(0.05, 0.05),
            centroid: SIMD2<Float>(0, 0)
        )
        XCTAssertEqual(zone, "CENTRE")
    }

    func test_cardinalZone_northEast() {
        let zone = DistortionAnalyzer.cardinalZone(
            of: SIMD2<Float>(0.5, -0.5),
            centroid: SIMD2<Float>(0, 0)
        )
        XCTAssertEqual(zone, "NORD-EST")
    }

    func test_cardinalZone_pureSouth() {
        let zone = DistortionAnalyzer.cardinalZone(
            of: SIMD2<Float>(0.05, 0.5),  // x dans la zone CENTRE, z au sud
            centroid: SIMD2<Float>(0, 0)
        )
        XCTAssertEqual(zone, "SUD")
    }

    // MARK: - Defensive cases

    func test_score_mismatchedBoundaryCount_returnsOne() {
        let p = SIMD2<Float>(0, 0)
        let asymmetric: [SIMD2<Float>] = [
            SIMD2(-1, -1),
            SIMD2( 1, -1),
            SIMD2( 0,  1),
        ]
        let score = DistortionAnalyzer.score(
            oldPosition: p,
            newPosition: p,
            oldBoundary: unitSquare,
            newBoundary: asymmetric
        )
        XCTAssertEqual(score, 1.0, "mismatched boundaries should not crash, must return 1")
    }
}
