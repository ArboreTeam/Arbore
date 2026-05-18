//
//  SceneUnderstandingControllerTests.swift
//  ArboreUiTests
//
//  Tests le throttle dynamique thermal-aware (#186 follow-up) qui
//  remplace le hard-cut à `.fair` par une cadence qui se dégrade
//  graduellement avec le thermal state.
//

import XCTest
import simd
@testable import ArboreUi

final class SceneUnderstandingControllerTests: XCTestCase {

    func test_effectiveThrottleSeconds_scalesWithThermalState() {
        let ctl = SceneUnderstandingController()
        ctl.throttleSeconds = 1.0   // 1 Hz base

        XCTAssertEqual(ctl.effectiveThrottleSeconds(for: .nominal), 1.0, accuracy: 1e-6,
                       ".nominal — full rate (1 Hz)")
        XCTAssertEqual(ctl.effectiveThrottleSeconds(for: .fair), 2.0, accuracy: 1e-6,
                       ".fair — half rate (0.5 Hz)")
        XCTAssertEqual(ctl.effectiveThrottleSeconds(for: .serious), 4.0, accuracy: 1e-6,
                       ".serious — quarter rate (0.25 Hz)")
        XCTAssertTrue(ctl.effectiveThrottleSeconds(for: .critical).isInfinite,
                      ".critical — hard cut (∞)")
    }

    func test_effectiveThrottleSeconds_respectsCustomBase() {
        // If we change the base throttle to 2s (0.5 Hz nominal), the
        // thermal multipliers scale accordingly.
        let ctl = SceneUnderstandingController()
        ctl.throttleSeconds = 2.0

        XCTAssertEqual(ctl.effectiveThrottleSeconds(for: .nominal), 2.0, accuracy: 1e-6)
        XCTAssertEqual(ctl.effectiveThrottleSeconds(for: .fair), 4.0, accuracy: 1e-6)
        XCTAssertEqual(ctl.effectiveThrottleSeconds(for: .serious), 8.0, accuracy: 1e-6)
    }

    // MARK: - Motion gating (#189 follow-up A)

    private func transform(translation t: SIMD3<Float>, forward: SIMD3<Float> = SIMD3<Float>(0, 0, -1)) -> simd_float4x4 {
        // Build a transform whose 3rd column is `-forward` (ARKit camera
        // looks toward -Z, so col2 = -forward). Translation in column 3.
        let z = -simd_normalize(forward)
        var m = matrix_identity_float4x4
        m.columns.2 = SIMD4<Float>(z.x, z.y, z.z, 0)
        m.columns.3 = SIMD4<Float>(t.x, t.y, t.z, 1)
        return m
    }

    func test_motionGate_alwaysAcceptsFirstFrame() {
        let ctl = SceneUnderstandingController()
        XCTAssertTrue(ctl.shouldIntegrateForMotion(cameraTransform: transform(translation: .zero)),
                      "first call has no baseline → must integrate")
    }

    func test_motionGate_rejectsSubThresholdTranslation() {
        let ctl = SceneUnderstandingController()
        ctl.motionGateTranslation = 0.05
        ctl.motionGateRotation = .pi   // disable rotation gate
        // Baseline.
        _ = ctl.shouldIntegrateForMotion(cameraTransform: transform(translation: .zero))
        // 2 cm later → below 5 cm threshold.
        let result = ctl.shouldIntegrateForMotion(cameraTransform: transform(translation: SIMD3<Float>(0.02, 0, 0)))
        XCTAssertFalse(result)
    }

    func test_motionGate_acceptsAboveThresholdTranslation() {
        let ctl = SceneUnderstandingController()
        ctl.motionGateTranslation = 0.05
        ctl.motionGateRotation = .pi
        _ = ctl.shouldIntegrateForMotion(cameraTransform: transform(translation: .zero))
        let result = ctl.shouldIntegrateForMotion(cameraTransform: transform(translation: SIMD3<Float>(0.10, 0, 0)))
        XCTAssertTrue(result)
    }

    func test_motionGate_acceptsRotationEvenWithoutTranslation() {
        let ctl = SceneUnderstandingController()
        ctl.motionGateTranslation = .greatestFiniteMagnitude   // disable translation
        ctl.motionGateRotation = .pi / 36   // 5°
        _ = ctl.shouldIntegrateForMotion(cameraTransform: transform(translation: .zero, forward: SIMD3<Float>(0, 0, -1)))
        // Rotate 10° around Y axis.
        let angle: Float = .pi / 18
        let rotated = SIMD3<Float>(sin(angle), 0, -cos(angle))
        let result = ctl.shouldIntegrateForMotion(cameraTransform: transform(translation: .zero, forward: rotated))
        XCTAssertTrue(result)
    }
}
