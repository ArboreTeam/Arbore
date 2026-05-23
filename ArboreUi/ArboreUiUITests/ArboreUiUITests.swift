//
//  ArboreUiUITests.swift
//  ArboreUiUITests
//
//  Created by Hugo Rath on 14/03/2025.
//

import XCTest

/// Boot-flow smoke tests (#66, first foothold of XCUITest coverage).
///
/// Scope chosen for pre-jury :
///  - The app launches and reaches an interactive state (not crashed,
///    not stuck on a blank/error screen).
///  - State-agnostic : the host simulator may have a persisted Firebase
///    session (lands on Home) or not (lands on Login). Both are valid
///    boot outcomes ; we just assert the app reached one of them.
///
/// Out of scope (post-jury follow-up for #66) :
///  - Deterministic logged-out launches (needs a test-mode hook in
///    AppDelegate that actually flushes the Firebase keychain before
///    LoginView's auth observer fires — a `CommandLine.arguments`
///    flag was attempted but Firebase Auth had already restored the
///    session by the time the observer mounted).
///  - Login flow, garden creation, plant placement end-to-end (needs
///    a test backend tenant + camera-less AR placeholder).
final class ArboreUiUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        // Unconditional screenshot for the test report — useful for
        // visual-only regressions (truncated text, wrong colour, …)
        // that XCTAssert can't catch.
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "End-of-test state"
        shot.lifetime = .keepAlways
        add(shot)
    }

    // MARK: - Smoke tests

    /// The app launches, the splash plays out, and the process is still
    /// in the foreground. Catches the "white screen of death" /
    /// fatalError-on-launch regression class : missing required
    /// Info.plist key, fatalError in AppConfig, broken Firebase init,
    /// missing assets.
    @MainActor
    func test_appLaunches_reachesForegroundState() throws {
        // 8 s covers the 2 s splash plus cold-start jitter on CI runners.
        sleep(8)
        XCTAssertEqual(
            app.state, .runningForeground,
            "App should be in foreground after launch — crash, watchdog kill, or stuck launch screen otherwise."
        )
    }

    /// After the splash, the app exposes an interactive UI : at least
    /// one tappable button is in the view hierarchy. Catches the
    /// regression "scene mounted but body returned EmptyView" without
    /// over-specifying which screen we land on (Home if a Firebase
    /// session is persisted, Login otherwise — both expose buttons).
    @MainActor
    func test_appLaunches_exposesAtLeastOneTappableControl() throws {
        sleep(8)
        XCTAssertGreaterThan(
            app.buttons.count, 0,
            "After launch the app should expose at least one tappable button — blank/error state otherwise."
        )
    }

    /// The app reaches one of the two known good entry surfaces :
    /// LoginView (unauthed, identified by its tagline) or the authed
    /// Home tab bar (identified by its 'Accueil' tab). Catches
    /// "rendered something but not what we expect" regressions like a
    /// stuck splash, an alert overlay covering the screen, or a wrong
    /// initial NavigationView.
    @MainActor
    func test_appLaunches_reachesEitherLoginOrHomeTab() throws {
        // Allow up to 12 s : splash + auth state restore + initial render.
        let deadline = Date().addingTimeInterval(12)
        var landed = false
        while Date() < deadline {
            if app.staticTexts["Grow with harmony"].exists
                || app.tabBars.buttons["Accueil"].exists {
                landed = true
                break
            }
            usleep(250_000)   // 0.25 s poll
        }
        XCTAssertTrue(
            landed,
            "App should reach LoginView (tagline 'Grow with harmony') or authed Home (tab 'Accueil') within 12 s."
        )
    }

    // MARK: - Performance baseline

    /// Captures cold launch time across builds so we notice regressions
    /// when an init path grows (e.g. CoreML model loading creeping into
    /// AppDelegate, blocking SwiftUI scene mount). Xcode re-baselines
    /// automatically on each re-record.
    @MainActor
    func test_launchPerformance() throws {
        if #available(iOS 13.0, *) {
            measure(metrics: [XCTApplicationLaunchMetric()]) {
                XCUIApplication().launch()
            }
        }
    }
}
