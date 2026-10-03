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
    /// the host records both displays between FOOTAGE-READY and FOOTAGE-END:
    /// `xcrun simctl io <udid> recordVideo [--display=external] …`, stopped
    /// with SIGINT. Every XCUITest action waits about a minute for idle while
    /// the keyboard proxy holds focus, so cut the scene from the recording.
    func testGlassesFootage() throws {
        let host = env["DEMO_HOST"] ?? ""
        let password = env["DEMO_PASSWORD"] ?? ""
        try XCTSkipIf(host.isEmpty || password.isEmpty, "DEMO_HOST / DEMO_PASSWORD not set")

        let app = XCUIApplication()
        // Big enough to read once the glasses are scaled into a phone-sized cut.
        app.launchArguments += ["-glassesFontSize", "24"]
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
        XCTAssertTrue(app.buttons["Text Size on Glasses"].waitForExistence(timeout: 30),
                      "not in glasses mode: \(app.debugDescription)")
        XCTAssertTrue(app.staticTexts["projects"].waitForExistence(timeout: 30),
                      "browser never listed the demo files: \(app.debugDescription)")
        // The login banner names the IP the connection came from, which is
        // whoever is recording. Clear it before anything is filmed.
        app.typeText("clear\n")
        Thread.sleep(forTimeInterval: 2)
        print("FOOTAGE-READY")
        Thread.sleep(forTimeInterval: 4)
        app.typeText("ls -la\n")
        Thread.sleep(forTimeInterval: 3)
        app.typeText("top\n")
        Thread.sleep(forTimeInterval: 10)
        print("FOOTAGE-END")
    }

    private func createHost(_ app: XCUIApplication, address: String, password: String) throws {
        app.navigationBars.buttons["Add"].tap()
        app.buttons["New Host"].tap()

        let label = app.textFields["Label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5), app.debugDescription)
        label.tap()
        label.typeText("review")
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
