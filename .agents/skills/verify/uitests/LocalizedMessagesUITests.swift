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

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
