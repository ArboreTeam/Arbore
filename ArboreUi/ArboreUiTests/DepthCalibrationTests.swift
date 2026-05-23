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

    // MARK: - RANSAC (Niveau 3 / #190)

    func test_fitAffineRANSAC_recoversParametersDespiteOutliers() {
        // 15 clean samples on `1/metric = 1.2·raw + 0.3`, mixed with
        // 5 wild outliers. Plain LS would drift ; RANSAC must lock
        // onto the inlier line.
        let a: Float = 1.2, b: Float = 0.3
        var samples: [Sample] = (1...15).map { i in
            let raw = Float(i) * 0.05
            return Sample(raw: raw, metric: 1 / (a * raw + b))
        }
        for _ in 0..<5 {
            samples.append(Sample(raw: Float.random(in: 0.1...1.0),
                                  metric: Float.random(in: 0.05...0.3)))
        }
        guard let result = DepthCalibration.fitAffineRANSAC(samples: samples) else {
            return XCTFail("RANSAC returned nil despite ≥5 inliers available")
        }
        XCTAssertEqual(result.fit.a, a, accuracy: 0.1)
        XCTAssertEqual(result.fit.b, b, accuracy: 0.1)
        XCTAssertGreaterThanOrEqual(result.inlierCount, 10)
    }

    func test_fitAffineRANSAC_returnsNilBelowMinInliers() {
        // <8 samples → no trustworthy fit. We deliberately do NOT
        // fall back to plain LS because 2-3 noisy anchors regularly
        // produced sign-flipped `a` values on device that polluted
        // the temporal-median smoothing for several ticks (cf
        // device log post-mortem 2026-05).
        let samples: [Sample] = [
            Sample(raw: 0.1, metric: 5.0),
            Sample(raw: 0.5, metric: 1.5),
        ]
        XCTAssertNil(DepthCalibration.fitAffineRANSAC(samples: samples))
    }

    func test_fitAffineRANSAC_returnsNilWithStrictMinInliersOnNoise() {
        // All-noise samples → no consensus model exists at high
        // minInliers requirement.
        let samples: [Sample] = (0..<20).map { _ in
            Sample(raw: Float.random(in: 0.1...1.0),
                   metric: Float.random(in: 0.5...5.0))
        }
        let result = DepthCalibration.fitAffineRANSAC(samples: samples, minInliers: 18)
        XCTAssertNil(result)
    }

    func test_fitAffineRANSAC_rejectsSignFlippedFits() {
        // 10 samples that perfectly fit a negative-slope affine model
        // (`a = -0.5`). RANSAC's outlier-rejection alone would happily
        // lock onto them, but the sanity guard rejects because raw
        // inverse-depth and metric distance must both rise together —
        // a negative slope is non-physical and was the root cause of
        // the `raw≈-7`, `raw≈-3` device log lines.
        let a: Float = -0.5, b: Float = 1.0
        let samples: [Sample] = (1...10).map { i in
            let raw = Float(i) * 0.1
            return Sample(raw: raw, metric: 1 / (a * raw + b))
        }
        XCTAssertNil(DepthCalibration.fitAffineRANSAC(samples: samples))
    }
}
