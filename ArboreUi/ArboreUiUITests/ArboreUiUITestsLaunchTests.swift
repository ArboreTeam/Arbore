//
//  ArboreUiUITestsLaunchTests.swift
//  ArboreUiUITests
//
//  Created by Hugo Rath on 14/03/2025.
//

import XCTest

final class ArboreUiUITestsLaunchTests: XCTestCase {

    override class var runsForEachTargetApplicationUIConfiguration: Bool {
        false
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testLaunch() throws {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.wait(for: .runningForeground, timeout: 15),
            "The application did not reach the foreground after launch."
        )

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Launch Screen"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
