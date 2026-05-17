//
//  DepthCalibrationTests.swift
//  ArboreUiTests
//
//  Tests pour le fit affine de calibration de depth (#186 Niveau 2,
//  fait suite à l'audit #188). On vérifie que `fitAffine` retrouve
//  bien les paramètres `(a, b)` synthétiques injectés, que `metric()`
//  inverse correctement, et que les cas dégénérés sont gérés.
//

import XCTest
@testable import ArboreUi

final class DepthCalibrationTests: XCTestCase {

    private typealias Fit = DepthCalibration.AffineFit
    private typealias Sample = DepthCalibration.Sample

    // MARK: - Roundtrip — fit retrouve les paramètres injectés

    func test_fitAffine_recoversParametersFromCleanSamples() {
        // Generate samples matching `1/metric = 1.2 · raw + 0.3`.
        let a: Float = 1.2
        let b: Float = 0.3
        let samples: [Sample] = (1...20).map { i in
            let raw = Float(i) * 0.05            // raw in [0.05, 1.0]
            let metric = 1 / (a * raw + b)
            return Sample(raw: raw, metric: metric)
        }
        guard let fit = DepthCalibration.fitAffine(samples: samples) else {
            return XCTFail("fitAffine returned nil on clean samples")
        }
        XCTAssertEqual(fit.a, a, accuracy: 1e-3)
        XCTAssertEqual(fit.b, b, accuracy: 1e-3)
    }

    func test_fitAffine_metricInversesBack() {
        // Samples on a perfect line `1/metric = 1.5·raw + 0.2` —
        // the LS fit should be exact, so `metric()` round-trips.
        let a: Float = 1.5, b: Float = 0.2
        let samples: [Sample] = [0.1, 0.3, 0.7, 1.2].map { raw in
            Sample(raw: raw, metric: 1 / (a * raw + b))
        }
        guard let fit = DepthCalibration.fitAffine(samples: samples) else {
            return XCTFail("expected non-nil fit")
        }
        for s in samples {
            XCTAssertEqual(fit.metric(raw: s.raw), s.metric, accuracy: 1e-3)
        }
    }

    func test_fitAffine_isRobustToOneOutlier() {
        // 9 samples on a clean line + 1 outlier far away. Without
        // RANSAC the LS fit drifts but stays in the right ballpark.
        let a: Float = 0.8, b: Float = 0.1
        var samples: [Sample] = (1...9).map { i in
            let raw = Float(i) * 0.1
            return Sample(raw: raw, metric: 1 / (a * raw + b))
        }
        samples.append(Sample(raw: 0.5, metric: 100.0))   // outlier
        let fit = DepthCalibration.fitAffine(samples: samples)!
        // ±50% tolerance is fine here — the contract is "stays sane",
        // not "perfect". RANSAC (#190) tightens this.
        XCTAssertEqual(fit.a, a, accuracy: 0.5)
    }

    // MARK: - Degenerate cases

    func test_fitAffine_returnsNilOnEmpty() {
        XCTAssertNil(DepthCalibration.fitAffine(samples: []))
    }

    func test_fitAffine_returnsNilOnSingleSample() {
        XCTAssertNil(DepthCalibration.fitAffine(samples: [
            Sample(raw: 0.5, metric: 2.0)
        ]))
    }

    func test_fitAffine_returnsNilWhenAllRawsAreIdentical() {
        // No variance in raw → can't fit a slope, returns nil.
        let samples: [Sample] = [
            Sample(raw: 0.5, metric: 1.0),
            Sample(raw: 0.5, metric: 2.0),
            Sample(raw: 0.5, metric: 3.0),
        ]
        XCTAssertNil(DepthCalibration.fitAffine(samples: samples))
    }

    // MARK: - AffineFit helpers

    func test_metric_returnsInfinityNearSingularity() {
        // metric = 1 / (a·raw + b). When a·raw + b ≈ 0, metric → infinity.
        let fit = Fit(a: 1.0, b: 0)
        XCTAssertTrue(fit.metric(raw: 0).isInfinite || fit.metric(raw: 0).isNaN)
    }

    func test_equivalentInverseScale_matchesSinglePointModel() {
        // When b = 0, the affine model degenerates to the old
        // single-scale `metric = scale / raw` with scale = 1/a.
        let fit = Fit(a: 1 / 0.95, b: 0)
        XCTAssertEqual(fit.equivalentInverseScale ?? -1, 0.95, accuracy: 1e-5)
    }
}
