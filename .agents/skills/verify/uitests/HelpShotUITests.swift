import XCTest

/// Screenshots the Credentials & SSH Keys help topic.
///
/// The generated site manual proves the *content pipeline* (Swift source →
/// string catalog → HTML). This proves the app itself: that the new import
/// section is reachable, renders its markdown, and reads correctly on a phone
/// screen. Added for the 1.7 key-import help gap — the store listing and the
/// featuring nomination both sell import, so the in-app guide has to show it.
final class HelpShotUITests: XCTestCase {

    func testCredentialsHelpTopic() {
        let app = XCUIApplication()
        app.launch()

        let help = app.buttons["Help"]
        XCTAssertTrue(help.waitForExistence(timeout: 30), "Help button never appeared")
        help.tap()

        let topic = app.staticTexts["Credentials & SSH Keys"]
        XCTAssertTrue(topic.waitForExistence(timeout: 15), "help topic list never appeared")
        topic.tap()

        // HelpTopicView is a plain ScrollView/VStack, so every block exists in
        // the tree immediately — these assertions are the real verification and
        // the screenshots are the evidence.
        for expected in ["Import a key you already have",
                         "Or tap Choose File… to pick the key out of Files.",
                         "If the key has a passphrase, Pockterm asks for it once and stores it in the Keychain alongside the key."] {
            XCTAssertTrue(app.staticTexts[expected].waitForExistence(timeout: 10),
                          "missing from the rendered help topic: \(expected)")
        }

        // The old wording must be gone, not merely supplemented.
        XCTAssertFalse(app.staticTexts["For Key, select one of the keys you generated."].exists,
                       "the superseded 'keys you generated' wording is still rendering")

        shoot("1-help-credentials-top")
        app.swipeUp()
        shoot("2-help-credentials-import")
        app.swipeUp()
        shoot("3-help-credentials-pem")
    }

    /// The Glasses & External Displays topic, in the language the host asks
    /// for. TEST_RUNNER_HELP_LANG, TEST_RUNNER_HELP_BUTTON and
    /// TEST_RUNNER_HELP_TOPIC carry the language code and the localized Help
    /// button and topic title (from Localizable.xcstrings), so one test covers
    /// every language and the RTL and CJK layouts.
    func testGlassesHelpTopic() {
        let env = ProcessInfo.processInfo.environment
        let lang = env["HELP_LANG"] ?? "en"
        let app = XCUIApplication()
        app.launchArguments += ["-AppleLanguages", "(\(lang))", "-AppleLocale", lang]
        app.launch()

        let help = app.buttons[env["HELP_BUTTON"] ?? "Help"]
        XCTAssertTrue(help.waitForExistence(timeout: 30), "Help button never appeared")
        help.tap()

        let topic = app.staticTexts[env["HELP_TOPIC"] ?? "Glasses & External Displays"]
        XCTAssertTrue(topic.waitForExistence(timeout: 15), "glasses topic not in the list: \(app.debugDescription)")
        shoot("g\(lang)-0-list")
        topic.tap()
        Thread.sleep(forTimeInterval: 1)
        shoot("g\(lang)-1-topic")
    }

    private func shoot(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
    }
}
