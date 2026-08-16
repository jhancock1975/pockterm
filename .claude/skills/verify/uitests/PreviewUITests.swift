import XCTest

/// Drives the app through a watchable demo while `simctl io recordVideo` runs
/// alongside. Deliberately slow and deliberate: this is footage, not a test,
/// so every step holds long enough to read. The host's startupSnippet fills
/// the terminal, so nothing is typed — synthesized keystrokes each cost a 60s
/// quiescence timeout against the terminal's animating caret.
///
/// Beats are printed as BEAT|<name>|<seconds-since-start> so the editing step
/// can cut on real timings instead of guesses.
final class PreviewUITests: XCTestCase {

    private let env = ProcessInfo.processInfo.environment
    private func label(_ key: String, _ fallback: String) -> String {
        let v = env[key] ?? ""
        return v.isEmpty ? fallback : v
    }

    private var start = Date()
    private func beat(_ name: String) {
        print("BEAT|\(name)|\(String(format: "%.2f", Date().timeIntervalSince(start)))")
    }

    override func setUpWithError() throws { continueAfterFailure = false }

    func testRecordDemo() throws {
        let lang = label("SHOT_LANG", "en")
        let locale = label("SHOT_LOCALE", "en_US")

        let app = XCUIApplication()
        let quiescence = NSSelectorFromString("_setUsesQuiescenceWaiting:")
        if app.responds(to: quiescence) { app.perform(quiescence, with: nil) }
        app.launchArguments += ["-AppleLanguages", "(\(lang))", "-AppleLocale", locale]

        start = Date()
        app.launch()
        beat("launch")
        Thread.sleep(forTimeInterval: 2.5)

        // --- connect; the startup snippet fills the terminal ---------------
        // Matches the host's label rather than its address: filming runs
        // against the App Review demo box, not localhost.
        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", label("L_HOST", "mac"))).firstMatch
        XCTAssertTrue(hostRow.waitForExistence(timeout: 15), app.debugDescription)
        beat("host-list")
        Thread.sleep(forTimeInterval: 1.5)
        hostRow.tap()

        let alert = app.alerts.firstMatch
        if alert.waitForExistence(timeout: 5) {
            alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
        }
        Thread.sleep(forTimeInterval: 13)          // connect + snippet output
        beat("terminal-filled")
        Thread.sleep(forTimeInterval: 3)

        // --- live theme switch ---------------------------------------------
        let themeButton = app.buttons[label("L_THEME", "Terminal Theme")]
        if themeButton.waitForExistence(timeout: 8) {
            themeButton.tap()
            beat("theme-sheet")
            Thread.sleep(forTimeInterval: 3)

            // Two switches is enough to read as "live"; each interaction costs
            // a ~2 minute XCUITest stall, so they are not free.
            for name in ["Nord", "Solarized Light"] {
                let row = app.buttons.matching(
                    NSPredicate(format: "label CONTAINS %@", name)).firstMatch
                if row.exists { row.tap(); beat("theme-\(name)"); Thread.sleep(forTimeInterval: 2.2) }
            }
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
               .press(forDuration: 0.05,
                      thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.0)))
            Thread.sleep(forTimeInterval: 2.5)
            beat("theme-done")
        }

        // --- pinch to zoom ---------------------------------------------------
        app.otherElements.element(boundBy: 0).pinch(withScale: 2.0, velocity: 1.6)
        beat("zoom-in")
        Thread.sleep(forTimeInterval: 3)

        // --- SFTP browser over the same connection --------------------------
        let files = app.buttons[label("L_FILES", "Browse Files")]
        if files.waitForExistence(timeout: 5) {
            files.tap()
            beat("sftp")
            Thread.sleep(forTimeInterval: 5)
            let done = app.navigationBars.buttons.element(boundBy: 0)
            if done.exists { done.tap() }
            Thread.sleep(forTimeInterval: 1.5)
        }

        // --- settings, which is where the localization reads clearly --------
        let minimize = app.buttons[label("L_MINIMIZE", "Minimize")]
        if minimize.waitForExistence(timeout: 5) { minimize.tap() }
        Thread.sleep(forTimeInterval: 2)
        app.tabBars.buttons.element(boundBy: 4).tap()
        beat("settings")
        Thread.sleep(forTimeInterval: 3)
        beat("end")
    }
}
