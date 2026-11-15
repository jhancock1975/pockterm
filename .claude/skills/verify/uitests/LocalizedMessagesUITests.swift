import XCTest

/// Checks, in one language, the terminal theme and font names in the host
/// editor. "Default", "Light" and "System" were built as plain `String`s and
/// showed English in every language. Leaves the editor unsaved.
///
/// The labels to tap and expect come from the host, read from
/// Localizable.xcstrings, so one test covers every language:
///
///   TEST_RUNNER_L_LANG=fr TEST_RUNNER_L_JSON='{"Hosts":"Hôtes",…}' xcodebuild test-without-building …
final class LocalizedMessagesUITests: XCTestCase {

    private let env = ProcessInfo.processInfo.environment

    override func setUpWithError() throws { continueAfterFailure = true }

    func testThemeAndFontNamesAreLocalized() throws {
        let lang = env["L_LANG"] ?? ""
        let json = env["L_JSON"] ?? ""
        try XCTSkipIf(lang.isEmpty || json.isEmpty, "L_LANG / L_JSON not set")
        let l = try JSONDecoder().decode([String: String].self, from: Data(json.utf8))
        func t(_ key: String) -> String { l[key] ?? key }

        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(lang))", "-AppleLocale", lang]
        app.launch()
        app.tabBars.buttons[t("Hosts")].tap()

        app.navigationBars.buttons.element(boundBy: app.navigationBars.buttons.count - 1).tap()
        app.buttons[t("New Host")].tap()
        let label = app.textFields[t("Label")]
        XCTAssertTrue(label.waitForExistence(timeout: 5), app.debugDescription)
        label.tap(); label.typeText("i18n")
        let addr = app.textFields[t("Address")]
        addr.tap(); addr.typeText("127.0.0.9")
        app.swipeUp()

        let theme = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", t("Theme"))).firstMatch
        XCTAssertTrue(theme.waitForExistence(timeout: 5), app.debugDescription)
        theme.tap()
        XCTAssertTrue(app.buttons[t("Default")].waitForExistence(timeout: 5), "theme name Default: \(app.debugDescription)")
        XCTAssertTrue(app.buttons[t("Light")].exists, "theme name Light")
        if t("Light") != "Light" { XCTAssertFalse(app.buttons["Light"].exists, "English theme name still shown") }
        attach(app, name: "\(lang)-1-themes")
        app.buttons[t("Default")].tap()

        let font = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", t("Font"))).firstMatch
        font.tap()
        XCTAssertTrue(app.buttons[t("System")].waitForExistence(timeout: 5), "font name System: \(app.debugDescription)")
        attach(app, name: "\(lang)-2-fonts")
        app.buttons[t("System")].tap()
    }

    /// Issue #22's key screen: generate a key, open it, copy it. Every label
    /// must be in the language under test, not English.
    func testKeyDetailIsLocalized() throws {
        let lang = env["L_LANG"] ?? ""
        let json = env["L_JSON"] ?? ""
        try XCTSkipIf(lang.isEmpty || json.isEmpty, "L_LANG / L_JSON not set")
        let l = try JSONDecoder().decode([String: String].self, from: Data(json.utf8))
        func t(_ key: String) -> String { l[key] ?? key }

        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(lang))", "-AppleLocale", lang]
        app.launch()
        app.tabBars.buttons[t("Keychain")].tap()
        deleteKeys(app, deleteLabel: t("Delete"),
                   matching: "label BEGINSWITH '0-' OR label BEGINSWITH 'i18n-' OR label BEGINSWITH 'issue22-'")
        Thread.sleep(forTimeInterval: 1) // let a swipe-delete finish closing
        app.navigationBars.buttons.firstMatch.tap() // the + button
        let generate = app.buttons[t("Generate Ed25519 Key…")]
        XCTAssertTrue(generate.waitForExistence(timeout: 5), app.debugDescription)
        generate.tap()
        let alert = app.alerts[t("Generate Ed25519 Key")]
        XCTAssertTrue(alert.waitForExistence(timeout: 5), app.debugDescription)
        // "0-" sorts above every real key, so the row is on screen to tap.
        let label = "0-\(lang)-\(Int(Date().timeIntervalSince1970))"
        alert.textFields.firstMatch.tap()
        alert.textFields.firstMatch.typeText(label)
        alert.buttons[t("Generate")].tap()

        let row = app.staticTexts[label]
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        // The new row animates in; a tap mid-animation can land on nothing.
        Thread.sleep(forTimeInterval: 1)
        row.tap()
        if !app.staticTexts[t("Public Key")].waitForExistence(timeout: 3), row.exists { row.tap() }

        for key in ["Public Key", "Label", "Type"] {
            XCTAssertTrue(app.staticTexts[t(key)].waitForExistence(timeout: 5), "\(key): \(app.debugDescription)")
        }
        let footer = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'authorized_keys'")).firstMatch
        XCTAssertTrue(footer.exists, "footer missing")
        XCTAssertFalse(footer.label.hasPrefix("Add this line"), "English footer: \(footer.label)")
        XCTAssertTrue(app.buttons[t("Share Public Key")].exists, "Share: \(app.debugDescription)")
        let copy = app.buttons[t("Copy Public Key")]
        XCTAssertTrue(copy.exists, "Copy: \(app.debugDescription)")
        for english in ["Copy Public Key", "Share Public Key", "Public Key"] where t(english) != english {
            XCTAssertFalse(app.buttons[english].exists || app.staticTexts[english].exists, "English still shown: \(english)")
        }
        attach(app, name: "\(lang)-k22-detail")
        copy.tap()
        XCTAssertTrue(app.buttons[t("Copied")].waitForExistence(timeout: 3), "Copied: \(app.debugDescription)")
        attach(app, name: "\(lang)-k22-copied")
        // The key is left behind; the next run's opening deleteKeys clears it.
    }

    /// Swipe-deletes every key row whose title matches, so test keys do not
    /// pile up in the simulator and push new rows off screen.
    private func deleteKeys(_ app: XCUIApplication, deleteLabel: String, matching predicate: String) {
        for _ in 0..<40 {
            let cell = app.cells.containing(NSPredicate(format: predicate)).firstMatch
            guard cell.waitForExistence(timeout: 1) else { return }
            // Swipe-to-delete comes from the trailing edge, which is the left in RTL.
            if ["ar", "he"].contains(env["L_LANG"] ?? "") { cell.swipeRight() } else { cell.swipeLeft() }
            // The swipe button is the system's, so match its identifier too.
            let delete = app.buttons.matching(NSPredicate(
                format: "label == %@ OR identifier == 'Delete'", deleteLabel)).firstMatch
            guard delete.waitForExistence(timeout: 2) else { return }
            delete.tap()
        }
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
