import XCTest

/// Captures the four App Store screenshots in whatever language the runner is
/// pointed at. Navigation labels are localized, so every label this driver
/// taps is passed in from the host via TEST_RUNNER_ environment variables,
/// read straight out of Localizable.xcstrings. Nothing here hardcodes English.
///
///   TEST_RUNNER_SHOT_LANG=ar TEST_RUNNER_SHOT_LOCALE=ar_SA \
///   TEST_RUNNER_L_THEME='سمة الطرفية' … xcodebuild test-without-building …
///
/// `testSetupHost` runs once in English to create the key/host and accept the
/// TOFU prompt; the capture runs then reuse that stored state.
final class ShotsUITests: XCTestCase {

    private let env = ProcessInfo.processInfo.environment
    private func label(_ key: String, _ fallback: String) -> String {
        let v = env[key] ?? ""
        return v.isEmpty ? fallback : v
    }

    /// Absolute path of the demo repo on the Mac, cd'd into so the terminal
    /// shows something worth photographing.
    private var demoPath: String { env["SHOT_DEMO_PATH"] ?? "~" }

    override func setUpWithError() throws { continueAfterFailure = false }

    // MARK: - one-time setup (English)

    func testSetupHost() throws {
        let app = XCUIApplication()
        app.launch()

        // Key first.
        app.tabBars.buttons.element(boundBy: 2).tap()          // Keychain
        let existing = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'ssh-ed25519'")).firstMatch
        if !existing.waitForExistence(timeout: 2) {
            app.navigationBars.buttons.firstMatch.tap()
            let alert = app.alerts.firstMatch
            XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
            alert.textFields.firstMatch.tap()
            alert.textFields.firstMatch.typeText("verify")
            alert.buttons["Generate"].tap()
        }
        let pub = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'ssh-ed25519'")).firstMatch
        XCTAssertTrue(pub.waitForExistence(timeout: 5), app.debugDescription)
        print("PUBKEY_BEGIN>>>\(pub.label)<<<PUBKEY_END")
    }

    // MARK: - capture

    func testCapture() throws {
        let lang = label("SHOT_LANG", "en")
        let locale = label("SHOT_LOCALE", "en_US")

        let app = XCUIApplication()
        // The terminal caret animates forever, so XCUITest's "wait for the app
        // to idle" never succeeds and burns its full 60s timeout on *every*
        // interaction. Passing nil sets the private flag to NO. This target is
        // a temporary local driver that is never shipped.
        let quiescence = NSSelectorFromString("_setUsesQuiescenceWaiting:")
        if app.responds(to: quiescence) { app.perform(quiescence, with: nil) }

        app.launchArguments += ["-AppleLanguages", "(\(lang))", "-AppleLocale", locale]
        app.launch()

        // --- connect -------------------------------------------------------
        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'localhost'")).firstMatch
        XCTAssertTrue(hostRow.waitForExistence(timeout: 15),
                      "no localhost host — run testSetupHost first\n\(app.debugDescription)")
        hostRow.tap()

        // TOFU should already be accepted; accept again if this is a fresh store.
        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 6) {
            alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
        }

        // The host's startupSnippet fills the terminal on connect, so there is
        // nothing to type — which matters, because every synthesized keystroke
        // costs a quiescence timeout.
        Thread.sleep(forTimeInterval: 12)
        shoot("2-terminal-theme")

        // --- 1: theme sheet over the live terminal -------------------------
        let themeButton = app.buttons[label("L_THEME", "Terminal Theme")]
        XCTAssertTrue(themeButton.waitForExistence(timeout: 8),
                      "theme button not found\n\(app.debugDescription)")
        themeButton.tap()
        Thread.sleep(forTimeInterval: 2.5)
        shoot("1-live-theme-switch")

        // The sheet stays up after a tap by design; swipe it away.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
           .press(forDuration: 0.05,
                  thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0)))
        Thread.sleep(forTimeInterval: 2.5)

        // --- 3: pinch to zoom the terminal ---------------------------------
        let terminal = app.otherElements.element(boundBy: 0)
        terminal.pinch(withScale: 2.2, velocity: 2.2)
        shoot("3-pinch-zoom-reset")            // HUD is brief — shoot immediately
        Thread.sleep(forTimeInterval: 2)

        // --- 4: Settings › Connection --------------------------------------
        let minimize = app.buttons[label("L_MINIMIZE", "Minimize")]
        if minimize.waitForExistence(timeout: 5) { minimize.tap() }
        Thread.sleep(forTimeInterval: 2)

        app.tabBars.buttons.element(boundBy: 4).tap()     // Settings
        Thread.sleep(forTimeInterval: 1.5)
        let connection = app.buttons[label("L_CONNECTION", "Connection")].firstMatch
        if connection.waitForExistence(timeout: 5) {
            connection.tap()
        } else {
            app.staticTexts[label("L_CONNECTION", "Connection")].firstMatch.tap()
        }
        Thread.sleep(forTimeInterval: 2.5)
        shoot("4-keepalive-setting")
    }

    // MARK: - helpers

    /// Full-device screenshot at native resolution (1320x2868 on a Pro Max),
    /// which is exactly what App Store Connect wants.
    private func shoot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: shot)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
