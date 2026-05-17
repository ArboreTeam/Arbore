//
//  SceneUnderstandingControllerTests.swift
//  ArboreUiTests
//
//  Tests le throttle dynamique thermal-aware (#186 follow-up) qui
//  remplace le hard-cut à `.fair` par une cadence qui se dégrade
//  graduellement avec le thermal state.
//

import XCTest
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
}
