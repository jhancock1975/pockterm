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

    /// One-time: point the app at a provider so the assistant can answer during
    /// filming. Run once per simulator, before testRecordDemo.
    ///
    /// The key arrives in POCKTERM_AI_KEY and is typed into a SecureField, so
    /// it is masked on screen and never reaches a screenshot or the recording.
    /// It does land in that simulator's Keychain — erase the simulator when
    /// filming is done.
    func testConfigureAssistant() throws {
        let key = env["POCKTERM_AI_KEY"] ?? ""
        try XCTSkipIf(key.isEmpty, "POCKTERM_AI_KEY not set")

        let app = XCUIApplication()
        let quiescence = NSSelectorFromString("_setUsesQuiescenceWaiting:")
        if app.responds(to: quiescence) { app.perform(quiescence, with: nil) }
        app.launch()

        app.tabBars.buttons.element(boundBy: 4).tap()
        let assistantRow = app.buttons["AI Assistant"].firstMatch
        XCTAssertTrue(assistantRow.waitForExistence(timeout: 15), app.debugDescription)
        assistantRow.tap()

        // The provider is set straight in the SwiftData store before this runs
        // — the Picker renders as a Form row rather than a button and driving
        // it silently left the provider on Anthropic, which stores the key
        // under the wrong provider and disables Test Connection. Assert it,
        // because getting this wrong is invisible until the scene is filmed.
        XCTAssertTrue(app.staticTexts["OpenRouter API Key"].waitForExistence(timeout: 10),
                      "provider is not OpenRouter\n" + app.debugDescription)

        let field = app.secureTextFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 8), app.debugDescription)
        field.tap()
        field.typeText(key)

        // The keyboard's accessory toolbar is drawn over the Save Key row, so
        // tapping Save Key while the keyboard is up lands on the toolbar and
        // silently does nothing. Dismiss first — that is what the chip is for.
        let dismiss = app.buttons["Dismiss Keyboard"].firstMatch
        if dismiss.exists { dismiss.tap() } else { app.keyboards.buttons["return"].tap() }
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Save Key"].firstMatch.tap()

        // The placeholder flips once a key is in the Keychain, so this is the
        // app's own answer to "did it store", not an assumption.
        XCTAssertTrue(app.secureTextFields["Replace API key"].waitForExistence(timeout: 8),
                      "key was not stored\n" + app.debugDescription)

        // Proves the key works now rather than halfway through a 15-minute take.
        let test = app.buttons["Test Connection"].firstMatch
        if test.waitForExistence(timeout: 5) {
            test.tap()
            Thread.sleep(forTimeInterval: 15)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "ai-settings"
        shot.lifetime = .keepAlways
        add(shot)
        print("BEAT|assistant-configured|0.00")
    }

    /// Conversations are stored per host, so one must survive the app being
    /// killed. Sends a turn, restarts the app, and looks for it again.
    func testAssistantPersistence() throws {
        let app = XCUIApplication()
        let quiescence = NSSelectorFromString("_setUsesQuiescenceWaiting:")
        if app.responds(to: quiescence) { app.perform(quiescence, with: nil) }
        app.launch()

        let marker = "persistence check \(Int(Date().timeIntervalSince1970) % 100000)"

        func openAssistant() {
            let hostRow = app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "mac")).firstMatch
            XCTAssertTrue(hostRow.waitForExistence(timeout: 20), app.debugDescription)
            hostRow.tap()
            let alert = app.alerts.firstMatch
            if alert.waitForExistence(timeout: 5) {
                alert.buttons.element(boundBy: alert.buttons.count - 1).tap()
            }
            Thread.sleep(forTimeInterval: 12)
            let assistant = app.buttons["AI Assistant"].firstMatch
            XCTAssertTrue(assistant.waitForExistence(timeout: 15), app.debugDescription)
            assistant.tap()
        }

        openAssistant()
        let prompt = app.textFields.firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 10), app.debugDescription)
        prompt.tap()
        prompt.typeText(marker)
        let hide = app.buttons["Dismiss Keyboard"].firstMatch
        if hide.exists { hide.tap() }
        app.buttons["Send"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 25)

        // Kill it outright — the case that used to lose everything.
        app.terminate()
        Thread.sleep(forTimeInterval: 3)
        app.launch()
        openAssistant()

        let restored = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", marker)).firstMatch
        XCTAssertTrue(restored.waitForExistence(timeout: 20),
                      "conversation did not survive a restart\n" + app.debugDescription)
        print("BEAT|persistence-verified|0.00")
    }

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
            // Theme names are untranslated literals, so the same match works in
            // every language. Falls back to staticTexts because the row is not
            // always exposed as a button, and the English take found neither.
            for name in ["Nord", "Solarized Light"] {
                let predicate = NSPredicate(format: "label CONTAINS %@", name)
                var row = app.buttons.matching(predicate).firstMatch
                if !row.waitForExistence(timeout: 3) {
                    row = app.staticTexts.matching(predicate).firstMatch
                }
                if row.exists && row.isHittable {
                    row.tap()
                    beat("theme-\(name)")
                    Thread.sleep(forTimeInterval: 2.2)
                } else {
                    print("BEAT|theme-\(name)-MISSING|0.00")
                }
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

        // --- the assistant, answering about what is on screen ----------------
        // Skipped rather than failed when unconfigured: a missing key should
        // cost the AI scene, not the whole take.
        let assistant = app.buttons[label("L_ASSISTANT", "AI Assistant")]
        if assistant.waitForExistence(timeout: 5) {
            assistant.tap()
            beat("assistant-open")
            Thread.sleep(forTimeInterval: 2.5)

            let prompt = app.textFields.firstMatch
            if prompt.waitForExistence(timeout: 8) {
                prompt.tap()
                // One typeText, not one per character — and short, because
                // every keystroke is billed against a live API key.
                prompt.typeText(label("L_PROMPT", "What is using the most memory?"))

                // Put the keyboard away before anything else: it covers half
                // the sheet, so the answer would be filmed behind it. It also
                // keeps whichever input method the language run happens to be
                // using out of shot.
                let hide = app.buttons[label("L_HIDE", "Dismiss Keyboard")].firstMatch
                if hide.exists { hide.tap() }
                beat("assistant-typed")
                Thread.sleep(forTimeInterval: 1.5)

                app.buttons[label("L_SEND", "Send")].firstMatch.tap()
                beat("assistant-sent")

                // The assistant ships defaulting to "Confirm everything", so
                // it proposes a command and waits. Without this tap the scene
                // is a permission card that never resolves — which is what the
                // first take filmed. Tapping Run shows the approval AND the
                // answer, which is the honest version of the feature.
                let run = app.buttons[label("L_RUN", "Run")].firstMatch
                if run.waitForExistence(timeout: 30) {
                    Thread.sleep(forTimeInterval: 2.5)   // let it be readable
                    run.tap()
                    beat("assistant-approved")
                }
                // Long enough for the command to run and the answer to stream.
                Thread.sleep(forTimeInterval: 22)
                beat("assistant-answered")
                Thread.sleep(forTimeInterval: 3)
            }

            let done = app.buttons[label("L_DONE", "Done")].firstMatch
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
