import XCTest

/// Pre-submission check: log in to the App Review demo host the way a reviewer
/// does — new host, new identity with password auth, connect, accept the host
/// key. Run it after scripts/provision-demo-host.sh and before submitting.
///
/// Host and password arrive as TEST_RUNNER_DEMO_HOST / TEST_RUNNER_DEMO_PASSWORD
/// so they never touch a file in the repo. The password goes into a
/// SecureField, so it is masked in every screenshot.
///
/// The test only proves the app reached a live session. Confirm the other end
/// while it holds the session open: `who` on the demo host shows the demo user
/// on a pts. That is printed as HOLDING>>> so the caller knows when to look.
final class DemoHostUITests: XCTestCase {

    private let env = ProcessInfo.processInfo.environment

    override func setUpWithError() throws { continueAfterFailure = false }

    func testReviewerLogin() throws {
        let host = env["DEMO_HOST"] ?? ""
        let password = env["DEMO_PASSWORD"] ?? ""
        try XCTSkipIf(host.isEmpty || password.isEmpty, "DEMO_HOST / DEMO_PASSWORD not set")

        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Hosts"].tap()

        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", host)).firstMatch
        if !hostRow.waitForExistence(timeout: 2) {
            try createHost(app, address: host, password: password)
        }
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()

        let hostKeyAlert = app.alerts["Verify Host Key"]
        if hostKeyAlert.waitForExistence(timeout: 15) {
            attach(app, name: "1-host-key")
            // TEST_RUNNER_DEMO_ACCEPT_DELAY: read the fingerprint first, as a
            // careful reviewer does. Citadel's ten-second login timer used to
            // fail anyone who took longer than that.
            if let delay = Double(env["DEMO_ACCEPT_DELAY"] ?? "") { Thread.sleep(forTimeInterval: delay) }
            hostKeyAlert.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Accept'")).firstMatch.tap()
        }

        let failed = app.staticTexts["Connection Failed"]
        let spinner = app.activityIndicators.firstMatch
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if failed.exists { XCTFail("connection failed: \(app.debugDescription)") }
            if !spinner.exists { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertFalse(spinner.exists, "still connecting after 30s")
        Thread.sleep(forTimeInterval: 3)
        XCTAssertFalse(failed.exists, "connection failed: \(app.debugDescription)")
        attach(app, name: "2-connected")

        print("HOLDING>>>\(Date().timeIntervalSince1970)<<<")
        Thread.sleep(forTimeInterval: 25)
        XCTAssertFalse(failed.exists, "session dropped while held")
        attach(app, name: "3-still-connected")
    }

    /// Pre-submission check for SFTP: the reviewer's host, opened in the file
    /// browser from the terminal's top bar. Expects the folders that the demo
    /// host's home directory is seeded with (projects, logs).
    func testReviewerFiles() throws {
        let host = env["DEMO_HOST"] ?? ""
        let password = env["DEMO_PASSWORD"] ?? ""
        try XCTSkipIf(host.isEmpty || password.isEmpty, "DEMO_HOST / DEMO_PASSWORD not set")

        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Hosts"].tap()
        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", host)).firstMatch
        if !hostRow.waitForExistence(timeout: 2) {
            try createHost(app, address: host, password: password)
        }
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()
        let hostKeyAlert = app.alerts["Verify Host Key"]
        if hostKeyAlert.waitForExistence(timeout: 15) {
            hostKeyAlert.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Accept'")).firstMatch.tap()
        }
        let files = app.buttons["Browse Files"]
        XCTAssertTrue(files.waitForExistence(timeout: 30), app.debugDescription)
        Thread.sleep(forTimeInterval: 2)
        files.tap()
        let listed = app.staticTexts["projects"]
        let failed = app.staticTexts["SFTP Error"]
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, !listed.exists, !failed.exists { Thread.sleep(forTimeInterval: 0.5) }
        attach(app, name: "f1-files")
        XCTAssertTrue(listed.exists, "SFTP didn't list the demo files: \(app.debugDescription)")
    }

    /// Demo footage for glasses mode, on the simulator from
    /// scripts/make-glasses-simulator. Connects to the demo host (so no Mac
    /// hostname or home directory gets filmed), then runs a short scene while
    /// the host records the glasses with `xcrun simctl io <udid> recordVideo
    /// --display=external …` (stopped with SIGINT) and screenshots the phone
    /// in a loop, because simctl records one display at a time.
    ///
    /// SHOT_LANG / SHOT_LOCALE pick the app's language, as in
    /// PreviewUITests.testRecordDemo, and L_GLASSES_SIZE is "Text Size on
    /// Glasses" in that language. The host must already exist (run
    /// testReviewerLogin once in English first), because creating one drives
    /// English labels. The scene's beats are printed as
    /// BEAT|<name>|<seconds>|<unix-time> for scripts/cut-demo-take.
    func testGlassesFootage() throws {
        let host = env["DEMO_HOST"] ?? ""
        let password = env["DEMO_PASSWORD"] ?? ""
        try XCTSkipIf(host.isEmpty || password.isEmpty, "DEMO_HOST / DEMO_PASSWORD not set")
        let lang = env["SHOT_LANG"].flatMap { $0.isEmpty ? nil : $0 }
        let start = Date()
        func beat(_ name: String) {
            let now = Date()
            print("BEAT|\(name)|\(String(format: "%.2f", now.timeIntervalSince(start)))"
                  + "|\(String(format: "%.3f", now.timeIntervalSince1970))")
        }

        let app = XCUIApplication()
        // Taps and queries then skip the wait for an idle that never comes
        // while the keyboard proxy holds focus (typeText still waits).
        let quiescence = NSSelectorFromString("_setUsesQuiescenceWaiting:")
        if app.responds(to: quiescence) { app.perform(quiescence, with: nil) }
        // Big enough to read once the glasses are scaled into a phone-sized cut.
        app.launchArguments += ["-glassesFontSize", "24"]
        if let lang {
            app.launchArguments += ["-AppleLanguages", "(\(lang))",
                                    "-AppleLocale", env["SHOT_LOCALE"] ?? lang]
        }
        app.launch()
        app.tabBars.buttons.element(boundBy: 0).tap()
        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", host)).firstMatch
        if !hostRow.waitForExistence(timeout: 4) {
            try XCTSkipIf(lang != nil, "no host yet: run testReviewerLogin in English first")
            try createHost(app, address: host, password: password)
        }
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()
        let hostKeyAlert = app.alerts.firstMatch
        if hostKeyAlert.waitForExistence(timeout: 15) {
            hostKeyAlert.buttons.element(boundBy: hostKeyAlert.buttons.count - 1).tap()
        }
        let sizeLabel = env["L_GLASSES_SIZE"].flatMap { $0.isEmpty ? nil : $0 }
            ?? "Text Size on Glasses"
        XCTAssertTrue(app.buttons[sizeLabel].waitForExistence(timeout: 30),
                      "not in glasses mode: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["projects"].waitForExistence(timeout: 30),
                      "browser never listed the demo files: \(app.debugDescription)")
        // A login banner would name the IP the connection came from, which is
        // whoever is recording, so the filming host has a .hushlogin and the
        // screen holds only the prompt. Check any new host for this.
        Thread.sleep(forTimeInterval: 2)
        print("FOOTAGE-READY")
        beat("glasses-ready")
        // One line, typed once: with the keyboard proxy focused, typeText
        // waits a minute for idle, types, then waits another minute (the
        // quiescence switch above does not reach it). The beats around it
        // say nothing about when the keys landed, so cut from the picture.
        beat("glasses-type")
        app.typeText("ls -la; sleep 1; top\n")
        beat("glasses-typed")
        Thread.sleep(forTimeInterval: 8)
        beat("glasses-end")
        print("FOOTAGE-END")
    }

    private func createHost(_ app: XCUIApplication, address: String, password: String) throws {
        app.navigationBars.buttons["Add"].tap()
        app.buttons["New Host"].tap()

        let label = app.textFields["Label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5), app.debugDescription)
        label.tap()
        // DEMO_LABEL names the host in the list; the demo videos use "demo".
        label.typeText(env["DEMO_LABEL"].flatMap { $0.isEmpty ? nil : $0 } ?? "review")
        let addr = app.textFields["Address"]
        addr.tap()
        addr.typeText(address)

        app.buttons["New Credentials"].tap()
        let idLabel = app.textFields["Label"]
        XCTAssertTrue(idLabel.waitForExistence(timeout: 5), app.debugDescription)
        idLabel.tap()
        idLabel.typeText("demo")
        let user = app.textFields["Username"]
        user.tap()
        user.typeText("demo")
        app.segmentedControls.buttons["Password"].tap()
        let pw = app.secureTextFields["Password"]
        XCTAssertTrue(pw.waitForExistence(timeout: 5), app.debugDescription)
        pw.tap()
        pw.typeText(password)
        app.navigationBars.buttons["Save"].tap()

        let idPicker = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Credentials'")).firstMatch
        XCTAssertTrue(idPicker.waitForExistence(timeout: 5), app.debugDescription)
        idPicker.tap()
        // Earlier runs leave credentials of the same name behind; any will do.
        let demoItem = app.buttons["demo"].firstMatch
        XCTAssertTrue(demoItem.waitForExistence(timeout: 5), app.debugDescription)
        demoItem.tap()
        attach(app, name: "0-host-editor")
        app.navigationBars.buttons["Save"].tap()
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
