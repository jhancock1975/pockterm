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
        let demoItem = app.buttons["demo"]
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
