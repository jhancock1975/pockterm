import XCTest

/// Scripted driver for manual-style verification of the assistant-sheet
/// keyboard fix. Run phases individually with -only-testing.
final class VerifyDriverUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Phase 1: generate an Ed25519 key in the app and print its public key
    /// so the host can add it to ~/.ssh/authorized_keys.
    func testPhase1GenerateKey() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Keychain"].tap()

        // If a "verify" key already exists (rerun), just print it.
        let existing = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'ssh-ed25519'")).firstMatch
        if !existing.waitForExistence(timeout: 2) {
            app.navigationBars.buttons.firstMatch.tap() // the + button
            // Since key import (1.7), + opens a menu: Generate… / Import….
            let generate = app.buttons["Generate Ed25519 Key…"]
            if generate.waitForExistence(timeout: 2) { generate.tap() }
            let alert = app.alerts["Generate Ed25519 Key"]
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

    /// Phase 2: create identity + host for the Mac's sshd, connect, raise the
    /// terminal keyboard, open the assistant sheet, and check the input bar
    /// sits above the keyboard with focus.
    func testPhase2KeyboardFix() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Hosts"].tap()

        // Only build the host once; reruns reuse it.
        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'localhost'")).firstMatch
        if !hostRow.waitForExistence(timeout: 2) {
            try createHost(app)
        }
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()

        // TOFU host-key prompt on first connect.
        let hostKeyAlert = app.alerts["Verify Host Key"]
        if hostKeyAlert.waitForExistence(timeout: 8) {
            hostKeyAlert.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Accept'")).firstMatch.tap()
        }

        // Wait for the session to be connected (spinner gone, no failure view).
        let failed = app.staticTexts["Connection Failed"]
        let spinner = app.activityIndicators.firstMatch
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if failed.exists { XCTFail("connection failed: \(app.debugDescription)") }
            if !spinner.exists { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "1-connected")

        // Tap the terminal to raise its keyboard.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let kb = app.keyboards.firstMatch
        XCTAssertTrue(kb.waitForExistence(timeout: 5), "terminal keyboard never appeared")
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "2-terminal-keyboard-up")
        print("TERMINAL_KB_FRAME>>>\(kb.frame)<<<")

        // Open the assistant sheet while the keyboard is up — the bug path.
        app.buttons["AI Assistant"].tap()

        let promptField = app.textFields["Ask the assistant…"]
        XCTAssertTrue(promptField.waitForExistence(timeout: 5), app.debugDescription)
        // Auto-focus should re-raise the keyboard inside the sheet.
        XCTAssertTrue(kb.waitForExistence(timeout: 5), "assistant keyboard never appeared")
        Thread.sleep(forTimeInterval: 1.5)
        attach(app, name: "3-assistant-sheet")

        let fieldFrame = promptField.frame
        let kbFrame = kb.frame
        print("ASSISTANT_FIELD_FRAME>>>\(fieldFrame)<<<")
        print("ASSISTANT_KB_FRAME>>>\(kbFrame)<<<")
        let focused = (promptField.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
        print("ASSISTANT_FIELD_FOCUSED>>>\(focused)<<<")

        XCTAssertTrue(promptField.isHittable, "prompt field not hittable")
        XCTAssertLessThanOrEqual(fieldFrame.maxY, kbFrame.minY + 1,
            "input bar (maxY \(fieldFrame.maxY)) is covered by keyboard (minY \(kbFrame.minY))")
        XCTAssertTrue(focused, "prompt field did not auto-focus")

        // Type into it end-to-end to prove the field is live.
        promptField.typeText("hello")
        attach(app, name: "4-typed-into-prompt")
    }

    /// Probe: the assistant sheet's manual keyboard avoidance must also hold
    /// on the common paths — opening with no terminal keyboard up, and
    /// dismissing then reopening the sheet.
    func testPhase3AssistantWithoutTerminalKeyboard() throws {
        let app = XCUIApplication()
        app.launch()

        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'localhost'")).firstMatch
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()

        let spinner = app.activityIndicators.firstMatch
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline && spinner.exists {
            Thread.sleep(forTimeInterval: 0.5)
        }
        Thread.sleep(forTimeInterval: 2)

        let kb = app.keyboards.firstMatch
        print("PHASE3_PRE_KEYBOARD>>>\(kb.exists)<<<")

        // Round 1: open with no terminal keyboard up.
        app.buttons["AI Assistant"].tap()
        let promptField = app.textFields["Ask the assistant…"]
        XCTAssertTrue(promptField.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(kb.waitForExistence(timeout: 5), "keyboard never appeared")
        Thread.sleep(forTimeInterval: 1.5)
        attach(app, name: "5-assistant-no-terminal-kb")
        print("PHASE3_R1_FIELD>>>\(promptField.frame)<<< KB>>>\(kb.frame)<<<")
        XCTAssertTrue(promptField.isHittable, "round 1: prompt field not hittable")

        // Round 2: dismiss and reopen.
        app.navigationBars.buttons["Done"].tap()
        Thread.sleep(forTimeInterval: 1)
        app.buttons["AI Assistant"].tap()
        XCTAssertTrue(promptField.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(kb.waitForExistence(timeout: 5), "keyboard never appeared on reopen")
        Thread.sleep(forTimeInterval: 1.5)
        attach(app, name: "6-assistant-reopened")
        print("PHASE3_R2_FIELD>>>\(promptField.frame)<<< KB>>>\(kb.frame)<<<")
        XCTAssertTrue(promptField.isHittable, "round 2: prompt field not hittable")
    }

    /// Phase 4: the minimize button hides the terminal without disconnecting,
    /// and both re-entry paths (the bottom accessory pill, tapping the live
    /// host row) restore the same session rather than reconnecting.
    ///
    /// Note: `fullScreenCover` has no interactive swipe-down dismissal, so the
    /// chevron is the only way out — don't bother testing a drag gesture.
    /// Note: `app.tabBars` exists even while the cover is presented; use the
    /// "Minimize" button's existence to tell whether the terminal is on screen.
    func testPhase4MinimizeAndRestore() throws {
        let app = XCUIApplication()
        app.launch()

        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'localhost'")).firstMatch
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()

        let hostKeyAlert = app.alerts["Verify Host Key"]
        if hostKeyAlert.waitForExistence(timeout: 8) {
            hostKeyAlert.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Accept'")).firstMatch.tap()
        }
        let spinner = app.activityIndicators.firstMatch
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline && spinner.exists { Thread.sleep(forTimeInterval: 0.5) }
        Thread.sleep(forTimeInterval: 2)

        let minimize = app.buttons["Minimize"]
        let pill = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Resume session'")).firstMatch
        XCTAssertTrue(minimize.waitForExistence(timeout: 5), "terminal not up: \(app.debugDescription)")
        attach(app, name: "7-connected-before-minimize")

        // Minimize: terminal goes away, pill appears, session survives.
        minimize.tap()
        XCTAssertTrue(pill.waitForExistence(timeout: 5),
                      "no minimized-session pill: \(app.debugDescription)")
        XCTAssertFalse(minimize.exists, "terminal still on screen after minimize")
        attach(app, name: "8-minimized-pill")

        // The live host is marked in the list.
        XCTAssertTrue(app.images["Session open"].waitForExistence(timeout: 5),
                      "no live-session indicator on host row: \(app.debugDescription)")

        // Re-entry path 1: the pill.
        pill.tap()
        XCTAssertTrue(minimize.waitForExistence(timeout: 5),
                      "pill did not restore terminal: \(app.debugDescription)")
        // Still connected: no reconnect spinner, no failure view.
        XCTAssertFalse(app.staticTexts["Connection Failed"].exists, "session died across minimize")
        XCTAssertFalse(app.staticTexts["Session Closed"].exists, "session closed across minimize")
        attach(app, name: "9-restored-from-pill")

        // Re-entry path 2: tapping the live host row.
        minimize.tap()
        XCTAssertTrue(pill.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()
        XCTAssertTrue(minimize.waitForExistence(timeout: 5),
                      "host row did not restore session: \(app.debugDescription)")
        XCTAssertFalse(app.staticTexts["Connection Failed"].exists, "host row reconnected instead of resuming")
        attach(app, name: "10-restored-from-host-row")
    }

    /// Marketing capture: seeds a host, connects, runs a command for a live
    /// terminal hero shot, opens the assistant, and captures the key screens.
    /// Run AFTER testPhase1GenerateKey + authorizing the key on the Mac.
    /// Intended for the iPhone 17 Pro Max destination (6.9" = 1320x2868).
    func testCaptureMarketing() throws {
        let app = XCUIApplication()
        app.launch()

        // 1. Hosts list (seed the host if this is a clean install).
        app.tabBars.buttons["Hosts"].tap()
        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'localhost' OR label CONTAINS 'mac'")).firstMatch
        if !hostRow.waitForExistence(timeout: 2) {
            try createHost(app)
        }
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "sc1-hosts")

        // 2. Connect.
        hostRow.tap()
        let hostKeyAlert = app.alerts["Verify Host Key"]
        if hostKeyAlert.waitForExistence(timeout: 8) {
            hostKeyAlert.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Accept'")).firstMatch.tap()
        }
        let failed = app.staticTexts["Connection Failed"]
        let spinner = app.activityIndicators.firstMatch
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if failed.exists { XCTFail("connection failed: \(app.debugDescription)") }
            if !spinner.exists { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        Thread.sleep(forTimeInterval: 2)

        // 3. Run a couple of commands for a live hero shot, then hide the
        //    keyboard so the terminal fills the frame.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "terminal keyboard never appeared")
        app.typeText("uname -srm\n")
        Thread.sleep(forTimeInterval: 1)
        app.typeText("ls -la\n")
        Thread.sleep(forTimeInterval: 1.5)
        // Dismiss the keyboard: the Minimize/keyboard toolbar varies, so tap
        // the terminal and use the key bar's hide-keyboard control if present,
        // else just capture with the keyboard up.
        if app.buttons["Hide keyboard"].exists { app.buttons["Hide keyboard"].tap() }
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "sc2-terminal")

        // 4. Assistant sheet with a typed question.
        if app.buttons["AI Assistant"].exists {
            app.buttons["AI Assistant"].tap()
            let promptField = app.textFields["Ask the assistant…"]
            if promptField.waitForExistence(timeout: 5) {
                promptField.tap()
                promptField.typeText("Why is my disk almost full?")
                Thread.sleep(forTimeInterval: 1.5)
                attach(app, name: "sc3-assistant")
                if app.navigationBars.buttons["Done"].exists {
                    app.navigationBars.buttons["Done"].tap()
                }
            }
        }

        // 5. Minimize to reach the tabs, then capture Keychain.
        Thread.sleep(forTimeInterval: 1)
        if app.buttons["Minimize"].exists { app.buttons["Minimize"].tap() }
        Thread.sleep(forTimeInterval: 1)
        if app.tabBars.buttons["Keychain"].exists {
            app.tabBars.buttons["Keychain"].tap()
            Thread.sleep(forTimeInterval: 1)
            attach(app, name: "sc4-keychain")
        }
        // 6. Settings → AI Assistant config.
        if app.tabBars.buttons["Settings"].exists {
            app.tabBars.buttons["Settings"].tap()
            Thread.sleep(forTimeInterval: 0.5)
            if app.buttons["AI Assistant"].exists {
                app.buttons["AI Assistant"].tap()
                Thread.sleep(forTimeInterval: 1)
                attach(app, name: "sc5-ai-settings")
            }
        }
    }

    /// App Store 1.1 capture: connects, shows a colorful live terminal, then
    /// captures the four feature screens the listing highlights — live theme
    /// picker, themed terminals (gallery), pinch-zoom + reset pill, and the
    /// keep-alive setting. Run AFTER testPhase1GenerateKey + authorizing the key.
    /// Intended for the iPhone 17 Pro Max destination (6.9" = 1320x2868).
    func testCaptureAppStore() throws {
        let app = XCUIApplication()
        app.launch()

        // Connect (seed the host on a clean install).
        app.tabBars.buttons["Hosts"].tap()
        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'localhost' OR label CONTAINS 'mac'")).firstMatch
        if !hostRow.waitForExistence(timeout: 2) { try createHost(app) }
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()
        let hostKeyAlert = app.alerts["Verify Host Key"]
        if hostKeyAlert.waitForExistence(timeout: 8) {
            hostKeyAlert.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Accept'")).firstMatch.tap()
        }
        let failed = app.staticTexts["Connection Failed"]
        let spinner = app.activityIndicators.firstMatch
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if failed.exists { XCTFail("connection failed: \(app.debugDescription)") }
            if !spinner.exists { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        Thread.sleep(forTimeInterval: 2)

        // Colorful content so themes are visible. printf guarantees ANSI color
        // regardless of the remote shell's ls settings.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "terminal keyboard never appeared")
        // Move into a neutral demo repo and set a generic prompt so no personal
        // home-directory contents or hostname appear in the marketing shots.
        app.typeText("cd /tmp/pockterm-demo\n")
        Thread.sleep(forTimeInterval: 0.5)
        app.typeText("export PS1='aurora $ '\n")
        Thread.sleep(forTimeInterval: 0.4)
        app.typeText("clear\n")
        Thread.sleep(forTimeInterval: 0.5)
        app.typeText("ls -la\n")
        Thread.sleep(forTimeInterval: 0.8)
        app.typeText("git -c color.status=always status -sb\n")
        Thread.sleep(forTimeInterval: 0.8)
        app.typeText("git log --oneline --decorate -3\n")
        Thread.sleep(forTimeInterval: 1.0)
        hideKeyboard(app)
        attach(app, name: "as1-terminal-default")

        // 1. Live theme switch: open the picker, apply a visible theme so the
        //    terminal behind re-themes and the checkmark moves. (Solarized
        //    Dark/Light sit fully inside the medium detent — no scrolling.)
        let palette = app.buttons["Terminal Theme"]
        XCTAssertTrue(palette.waitForExistence(timeout: 5),
                      "palette button missing: \(app.debugDescription)")
        palette.tap()
        Thread.sleep(forTimeInterval: 1.2)
        tapThemeRow(app, "Solarized Dark")
        attach(app, name: "as2-theme-picker-live")

        // 2. Theme gallery: apply a light theme, dismiss the sheet, and capture
        //    the bare re-themed terminal with the keyboard down.
        tapThemeRow(app, "Solarized Light")
        dismissSheet(app)
        hideKeyboard(app)
        attach(app, name: "as3-theme-light-terminal")

        // 3. Pinch-zoom + reset pill (keyboard down for a clean frame).
        app.windows.firstMatch.pinch(withScale: 2.4, velocity: 1.4)
        Thread.sleep(forTimeInterval: 0.6)
        hideKeyboard(app)
        let resetPill = app.buttons["Reset zoom to default size"]
        XCTAssertTrue(resetPill.waitForExistence(timeout: 3),
                      "reset pill did not appear after pinch: \(app.debugDescription)")
        Thread.sleep(forTimeInterval: 0.4)
        attach(app, name: "as4-zoom-reset-pill")
        // Best-effort: the transient "Default size" HUD after tapping reset.
        resetPill.tap()
        Thread.sleep(forTimeInterval: 0.3)
        attach(app, name: "as5-zoom-default-hud")

        // 4. Keep-alive setting: minimize → Settings → Connection.
        Thread.sleep(forTimeInterval: 0.8)
        if app.buttons["Minimize"].exists { app.buttons["Minimize"].tap() }
        Thread.sleep(forTimeInterval: 1)
        if app.tabBars.buttons["Settings"].exists {
            app.tabBars.buttons["Settings"].tap()
            Thread.sleep(forTimeInterval: 0.6)
            let connection = app.buttons.matching(
                NSPredicate(format: "label CONTAINS 'Connection'")).firstMatch
            if connection.waitForExistence(timeout: 5) {
                connection.tap()
                Thread.sleep(forTimeInterval: 1)
                attach(app, name: "as6-keepalive-setting")
            }
        }
    }

    /// Taps a theme row in the open picker. Each row's accessibility label is
    /// the theme name concatenated with its preview text ("Nord, user@host…"),
    /// so match by CONTAINS rather than an exact label.
    private func tapThemeRow(_ app: XCUIApplication, _ name: String) {
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
        if row.waitForExistence(timeout: 3) { row.tap() }
        Thread.sleep(forTimeInterval: 0.8)
    }

    /// Dismisses the terminal's software keyboard via the key bar's hide-keyboard
    /// key. That key carries only the SF Symbol `keyboard.chevron.compact.down`
    /// (no text label) and is the last key in the horizontally scrollable bar,
    /// so swipe the bar left first, then try several label forms.
    private func hideKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.62))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.62)))
        Thread.sleep(forTimeInterval: 0.4)
        // The button's accessibility label is exactly "hide keyboard" (lowercase).
        // Do NOT use a CONTAINS 'keyboard' match — it also hits the system
        // "Next keyboard" switcher and flips the input language.
        let hk = app.buttons["hide keyboard"]
        if hk.waitForExistence(timeout: 2) {
            hk.tap()
            Thread.sleep(forTimeInterval: 0.7)
        }
    }

    /// Dismisses a medium-detent sheet with a downward drag from its grabber so
    /// the drag stays on the sheet and never taps the terminal behind it.
    private func dismissSheet(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.37))
            .press(forDuration: 0.05,
                   thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)))
        Thread.sleep(forTimeInterval: 1)
    }

    /// Measures typematic backspace: how many DEL bytes reach the terminal
    /// when the software keyboard's delete key and the key bar's Backspace
    /// are each held down. Read the counts back out of the app's log:
    ///   xcrun simctl spawn booted log show --last 10m \
    ///     --predicate 'eventMessage CONTAINS "POCKVERIFY"'
    /// Markers: 'Q' (0x51) before the software-keyboard hold, 'W' (0x57)
    /// before the key bar hold, 'E' (0x45) after.
    func testBackspaceRepeat() throws {
        let app = XCUIApplication()
        app.launch()

        app.tabBars.buttons["Hosts"].tap()
        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'localhost'")).firstMatch
        if !hostRow.waitForExistence(timeout: 2) {
            try createHost(app)
        }
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()

        let hostKeyAlert = app.alerts["Verify Host Key"]
        if hostKeyAlert.waitForExistence(timeout: 8) {
            hostKeyAlert.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Accept'")).firstMatch.tap()
        }
        let spinner = app.activityIndicators.firstMatch
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline && spinner.exists {
            Thread.sleep(forTimeInterval: 0.5)
        }
        Thread.sleep(forTimeInterval: 2)

        // Raise the terminal keyboard.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        let kb = app.keyboards.firstMatch
        XCTAssertTrue(kb.waitForExistence(timeout: 10), "terminal keyboard never appeared")
        Thread.sleep(forTimeInterval: 1.5)
        attach(app, name: "kb-up")

        print("KEYS>>>\(app.keyboards.keys.allElementsBoundByIndex.map(\.identifier))<<<")

        // Element queries are resolved once, for their frames; the holds go
        // through raw coordinates. Re-resolving at press time loses the key
        // ("No matches found for Descendants matching type Key") as the
        // keyboard redraws. XCUITest also delivers each press only after the
        // app goes idle — about 60 s later here, since the terminal caret
        // animates forever — so the printed timestamps do not line up with the
        // log. Read the bursts off the log in order instead.
        var del = app.keys["delete"]
        if !del.waitForExistence(timeout: 5) { del = app.buttons["delete"] }
        XCTAssertTrue(del.waitForExistence(timeout: 5), "no delete key: \(app.keyboards.debugDescription)")
        let delPoint = point(app, in: del.frame)

        // Burst 1 — software keyboard delete with nothing typed locally. This
        // is the ordinary case: whatever is on the command line came from the
        // shell, so SwiftTerm's text-input buffer is empty. Without the
        // hasText override iOS refuses to repeat at all.
        print("HOLD_1_EMPTY_BUFFER_SOFT_DELETE>>>\(Date().timeIntervalSince1970)<<<")
        delPoint.press(forDuration: 3.0)
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "1-after-empty-buffer-hold")

        // Burst 2 — same key, after typing ten characters. Even unfixed this
        // one repeats, but only ten times, and then stops mid-hold.
        app.typeText("abcdefghij")
        Thread.sleep(forTimeInterval: 1)
        print("HOLD_2_TYPED_TEXT_SOFT_DELETE>>>\(Date().timeIntervalSince1970)<<<")
        delPoint.press(forDuration: 3.0)
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "2-after-typed-text-hold")

        // Burst 3 — the key bar's own Backspace, whose repeat is ours.
        let barBackspace = app.buttons["Backspace"]
        if barBackspace.waitForExistence(timeout: 5) {
            print("HOLD_3_KEYBAR>>>\(Date().timeIntervalSince1970)<<< frame=\(barBackspace.frame) hittable=\(barBackspace.isHittable)")
            point(app, in: barBackspace.frame).press(forDuration: 3.0)
        } else {
            print("KEYBAR_BACKSPACE_MISSING>>>true<<<")
        }
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "3-after-keybar-hold")
    }

    /// Discovery for the "key bar covers the bottom lines" backlog item.
    /// Connects, raises the terminal keyboard, and dumps the element tree plus
    /// the frames that matter, so the occlusion can be measured rather than
    /// argued from the constraint in TerminalHostView.
    func testKeyBarOcclusionGeometry() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Hosts"].tap()

        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'localhost' OR label CONTAINS 'mac'")).firstMatch
        if !hostRow.waitForExistence(timeout: 2) {
            try createHost(app)
        }
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()

        let hostKeyAlert = app.alerts["Verify Host Key"]
        if hostKeyAlert.waitForExistence(timeout: 8) {
            hostKeyAlert.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Accept'")).firstMatch.tap()
        }

        let failed = app.staticTexts["Connection Failed"]
        let spinner = app.activityIndicators.firstMatch
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if failed.exists { XCTFail("connection failed: \(app.debugDescription)") }
            if !spinner.exists { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        Thread.sleep(forTimeInterval: 2)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "terminal keyboard never appeared")
        Thread.sleep(forTimeInterval: 1.5)

        print("GEOM>>> window=\(app.windows.firstMatch.frame)")
        print("GEOM>>> keyboard=\(app.keyboards.firstMatch.frame)")
        for name in ["esc", "ctrl", "tab"] {
            let b = app.buttons[name]
            if b.exists { print("GEOM>>> keybar button \(name)=\(b.frame)") }
        }
        // Fill the screen with numbered lines. Frame arithmetic through XCUI is
        // unreliable here (it reports the keyboard at minY 891 in an 874pt
        // window), so measure what a user actually sees: print more lines than
        // fit, and read which number ends up last.
        app.typeText("for i in $(seq 1 60); do echo \"LINE-$i\"; done\n")
        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "occlusion-filled-hardware-kb")

        // Now raise the software keyboard explicitly via the key bar's own
        // keyboard button, which is the state the bug report describes.
        let kbButton = app.buttons["Show Keyboard"]
        if kbButton.exists {
            kbButton.tap()
            Thread.sleep(forTimeInterval: 2)
            attach(app, name: "occlusion-filled-software-kb")
            print("GEOM>>> after show keyboard, keyboard=\(app.keyboards.firstMatch.frame)")
            for name in ["esc", "ctrl"] where app.buttons[name].exists {
                print("GEOM>>> keybar \(name)=\(app.buttons[name].frame)")
            }
        } else {
            print("GEOM>>> no 'Show Keyboard' button; buttons present:")
            for b in app.buttons.allElementsBoundByIndex.prefix(20) {
                print("GEOM>>>   \(b.label) \(b.frame)")
            }
        }

        // Note: there is no "keyboard down, key bar still visible" state to
        // test on a touch-only device. Dismissing the keyboard resigns the
        // terminal's first responder status and the key bar goes with it —
        // it is an inputAccessoryView. The docked bar seen at launch here is
        // the simulator's hardware keyboard, i.e. an external keyboard on
        // device. Tapping Hide Keyboard then typing fails with "Neither
        // element nor any descendant has keyboard focus", which is that same
        // fact showing up as a test error.
    }

    /// Screenshots the SFTP browser so the modification-date column can be
    /// read in the real app. SFTP v3 carries no creation time, so this is
    /// mtime — the same thing `ls -l` shows.
    func testFileBrowserShowsDates() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Hosts"].tap()

        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'localhost' OR label CONTAINS 'mac'")).firstMatch
        if !hostRow.waitForExistence(timeout: 2) { try createHost(app) }
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()

        let hostKeyAlert = app.alerts["Verify Host Key"]
        if hostKeyAlert.waitForExistence(timeout: 8) {
            hostKeyAlert.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Accept'")).firstMatch.tap()
        }
        let spinner = app.activityIndicators.firstMatch
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, spinner.exists { Thread.sleep(forTimeInterval: 0.5) }
        Thread.sleep(forTimeInterval: 2)

        let browse = app.buttons["Browse Files"]
        XCTAssertTrue(browse.waitForExistence(timeout: 10), "no Browse Files button")
        browse.tap()
        Thread.sleep(forTimeInterval: 6)
        attach(app, name: "files-with-dates")

        // Directories show permissions + date. Navigate somewhere with real
        // files so the widest case — permissions, size AND timestamp on one
        // line — is the thing actually looked at. `renders` holds hundred-MB
        // videos, which is the longest size string anything here produces.
        for dir in ["git", "adult", "renders"] {
            let row = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", dir)).firstMatch
            // The listing starts on dotfiles, so most targets are below the
            // fold; XCUI will not tap what it cannot see.
            var swipes = 0
            while !(row.exists && row.isHittable) && swipes < 12 {
                app.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(row.exists && row.isHittable,
                          "never brought \(dir) into view after \(swipes) swipes")
            row.tap()
            Thread.sleep(forTimeInterval: 5)
        }
        attach(app, name: "files-with-sizes-and-dates")
        for t in app.staticTexts.allElementsBoundByIndex.prefix(40) where t.label.contains("MB") || t.label.contains("KB") || t.label.contains("bytes") {
            print("SIZEROW>>> \(t.label)")
        }

        // Dump a few subtitles so the date is checkable as text, not only
        // by eye in the screenshot.
        for t in app.staticTexts.allElementsBoundByIndex.prefix(30) where t.label.contains("-") {
            print("FILEROW>>> \(t.label)")
        }
    }

    /// Drives the sort menu in the SFTP browser: name order, then date
    /// (newest first), then date reversed. Prints the visible subtitles at
    /// each step so the order is checkable as text, and screenshots the open
    /// menu so the toolbar crowding can be judged by eye.
    func testFileBrowserSortsByDate() throws {
        let app = XCUIApplication()
        app.launch()
        try openRendersDirectory(app)

        attach(app, name: "sort-1-by-name")
        dumpRows(app, stage: "NAME-ASC")

        // The sort control is the only arrow.up.arrow.down button in the bar.
        let sortButton = app.navigationBars.buttons["Sort"]
        XCTAssertTrue(sortButton.waitForExistence(timeout: 5),
                      "no Sort button in the toolbar: " + app.navigationBars.debugDescription)
        sortButton.tap()
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "sort-2-menu-open")

        let dateItem = app.buttons["Date"]
        XCTAssertTrue(dateItem.waitForExistence(timeout: 5), app.debugDescription)
        dateItem.tap()
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "sort-3-by-date-newest")
        dumpRows(app, stage: "DATE-DESC")

        // Choosing the active field again must flip to oldest-first.
        sortButton.tap()
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Date"].tap()
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "sort-4-by-date-oldest")
        dumpRows(app, stage: "DATE-ASC")
    }

    /// Connects and walks down to the directory with real files in it — the
    /// shared opening move for the two file-browser phases.
    private func openRendersDirectory(_ app: XCUIApplication) throws {
        app.tabBars.buttons["Hosts"].tap()

        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'localhost' OR label CONTAINS 'mac'")).firstMatch
        if !hostRow.waitForExistence(timeout: 2) { try createHost(app) }
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()

        let hostKeyAlert = app.alerts["Verify Host Key"]
        if hostKeyAlert.waitForExistence(timeout: 8) {
            hostKeyAlert.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Accept'")).firstMatch.tap()
        }
        let spinner = app.activityIndicators.firstMatch
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, spinner.exists { Thread.sleep(forTimeInterval: 0.5) }
        Thread.sleep(forTimeInterval: 2)

        let browse = app.buttons["Browse Files"]
        XCTAssertTrue(browse.waitForExistence(timeout: 10), "no Browse Files button")
        browse.tap()
        Thread.sleep(forTimeInterval: 6)

        for dir in ["git", "adult", "renders"] {
            let row = app.buttons.matching(
                NSPredicate(format: "label BEGINSWITH %@", dir)).firstMatch
            var swipes = 0
            while !(row.exists && row.isHittable) && swipes < 12 {
                app.swipeUp()
                swipes += 1
            }
            XCTAssertTrue(row.exists && row.isHittable,
                          "never brought \(dir) into view after \(swipes) swipes")
            row.tap()
            Thread.sleep(forTimeInterval: 5)
        }
    }

    /// Prints each visible row as "name | subtitle" so the order can be
    /// compared against `ls` on the Mac without reading a screenshot.
    private func dumpRows(_ app: XCUIApplication, stage: String) {
        for row in app.buttons.allElementsBoundByIndex.prefix(40) {
            let label = row.label
            guard label.contains("rw") || label.contains("rwx") else { continue }
            print("SORTROW[\(stage)]>>> \(label.replacingOccurrences(of: "\n", with: " | "))")
        }
    }

    /// Proves the caret stops blinking once the shell exits.
    ///
    /// A screenshot cannot show the absence of an animation, so this samples
    /// the terminal repeatedly and counts how many distinct frames come back.
    /// A blinking caret fades over 0.7s and autoreverses, so samples spread
    /// across a couple of seconds must differ; a steady one must not. The
    /// live session is measured first as a positive control — without it a
    /// caret that had simply stopped being drawn would pass.
    func testCaretStopsBlinkingWhenTheSessionDies() throws {
        let app = XCUIApplication()
        app.launch()
        try connectToMac(app)

        let terminal = app.textViews.firstMatch
        XCTAssertTrue(terminal.waitForExistence(timeout: 10), app.debugDescription)
        // The caret only animates while the terminal holds keyboard focus,
        // which is also the state someone is in when their session dies.
        terminal.tap()
        Thread.sleep(forTimeInterval: 2)

        let live = distinctFrames(of: terminal, samples: 8, gap: 0.25)
        print("CARET>>> live session: \(live) distinct frames")
        XCTAssertGreaterThan(live, 1,
                             "control failed: the caret was not blinking even while connected, "
                             + "so this phase cannot prove anything about the dead case")

        terminal.typeText("exit\n")
        let closed = app.staticTexts["Session Closed"]
        XCTAssertTrue(closed.waitForExistence(timeout: 20),
                      "shell never reported closed: " + app.debugDescription)
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "caret-after-session-died")

        let dead = distinctFrames(of: terminal, samples: 8, gap: 0.25)
        print("CARET>>> dead session: \(dead) distinct frames")
        XCTAssertEqual(dead, 1, "the caret is still animating after the shell exited")
    }

    /// Samples an element's rendering and returns how many of the frames
    /// differ. Anything still animating shows up as more than one.
    private func distinctFrames(of element: XCUIElement, samples: Int, gap: TimeInterval) -> Int {
        var seen = Set<Data>()
        for _ in 0..<samples {
            seen.insert(element.screenshot().pngRepresentation)
            Thread.sleep(forTimeInterval: gap)
        }
        return seen.count
    }

    /// Connects to the Mac's sshd and waits for the shell, without opening the
    /// file browser.
    private func connectToMac(_ app: XCUIApplication) throws {
        app.tabBars.buttons["Hosts"].tap()
        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'localhost' OR label CONTAINS 'mac'")).firstMatch
        if !hostRow.waitForExistence(timeout: 2) { try createHost(app) }
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()

        let hostKeyAlert = app.alerts["Verify Host Key"]
        if hostKeyAlert.waitForExistence(timeout: 8) {
            hostKeyAlert.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Accept'")).firstMatch.tap()
        }
        let spinner = app.activityIndicators.firstMatch
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline, spinner.exists { Thread.sleep(forTimeInterval: 0.5) }
        Thread.sleep(forTimeInterval: 3)
    }

    /// Runs emacs inside tmux over the real SSH session and screenshots the
    /// screen after each redraw-heavy action. The keystrokes are sent from the
    /// Mac with `tmux send-keys` (see `tmux-drive.sh` beside this file) rather than
    /// through XCUITest, because C-x C-s does not survive `typeText`.
    ///
    /// What to look for: the emacs menu bar must stay on the top row, the mode
    /// line must stay directly above tmux's status line, and no row may be
    /// duplicated or shifted. Compare against `tmux -L v capture-pane -p -t v`
    /// run on the Mac.
    func testTmuxEmacsModeLine() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Hosts"].tap()

        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'localhost' OR label CONTAINS 'mac'")).firstMatch
        if !hostRow.waitForExistence(timeout: 2) {
            try createHost(app)
        }
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()

        let hostKeyAlert = app.alerts["Verify Host Key"]
        if hostKeyAlert.waitForExistence(timeout: 8) {
            hostKeyAlert.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Accept'")).firstMatch.tap()
        }

        let failed = app.staticTexts["Connection Failed"]
        let spinner = app.activityIndicators.firstMatch
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if failed.exists { XCTFail("connection failed: \(app.debugDescription)") }
            if !spinner.exists { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        Thread.sleep(forTimeInterval: 2)

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "terminal keyboard never appeared")
        Thread.sleep(forTimeInterval: 1.5)

        app.typeText("$HOME/git/pockterm/.claude/skills/verify/tmux-drive.sh\n")

        Thread.sleep(forTimeInterval: 8)
        attach(app, name: "tmux-00-startup")
        Thread.sleep(forTimeInterval: 8)
        attach(app, name: "tmux-01-after-first-save")
        Thread.sleep(forTimeInterval: 9)
        attach(app, name: "tmux-02-after-paging")
        Thread.sleep(forTimeInterval: 8)
        attach(app, name: "tmux-03-after-repeated-saves")
    }

    /// The occlusion report as filed: **at initial login**, before anything
    /// forces a re-layout, with whatever key bar the user has saved.
    ///
    /// Measures the terminal's own element frame against the key bar buttons'.
    /// Those are real view frames — it is only `app.keyboards.frame` that lies
    /// on iOS 26 (it omits the predictive bar), so do not use that here.
    /// If the terminal's maxY is below a key bar button's minY, the terminal
    /// is drawn underneath the bar and the bottom rows are occluded.
    func testKeyBarOcclusionAtInitialLogin() throws {
        let app = XCUIApplication()
        app.launch()
        app.tabBars.buttons["Hosts"].tap()

        let hostRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'localhost' OR label CONTAINS 'mac'")).firstMatch
        if !hostRow.waitForExistence(timeout: 2) {
            try createHost(app)
        }
        XCTAssertTrue(hostRow.waitForExistence(timeout: 5), app.debugDescription)
        hostRow.tap()

        let hostKeyAlert = app.alerts["Verify Host Key"]
        if hostKeyAlert.waitForExistence(timeout: 8) {
            hostKeyAlert.buttons.matching(
                NSPredicate(format: "label BEGINSWITH 'Accept'")).firstMatch.tap()
        }
        let failed = app.staticTexts["Connection Failed"]
        let spinner = app.activityIndicators.firstMatch
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if failed.exists { XCTFail("connection failed: \(app.debugDescription)") }
            if !spinner.exists { break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "login-0-connected-no-keyboard")
        report(app, "before keyboard")

        // Raise the keyboard and measure immediately — no typing, nothing that
        // would force the layout to settle a second time.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "terminal keyboard never appeared")
        Thread.sleep(forTimeInterval: 1.0)
        attach(app, name: "login-1-keyboard-just-up")
        report(app, "keyboard just up")

        // Give it longer in case this is a settling problem rather than a
        // constant offset.
        Thread.sleep(forTimeInterval: 3.0)
        attach(app, name: "login-2-keyboard-settled")
        report(app, "keyboard settled")

        // Now fill the screen, which is what the earlier probe did first.
        app.typeText("for i in $(seq 1 60); do echo \"LINE-$i\"; done\n")
        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "login-3-after-output")
        report(app, "after output")
    }

    /// Prints the terminal's frame against the key bar's, in window space.
    private func report(_ app: XCUIApplication, _ stage: String) {
        let window = app.windows.firstMatch.frame
        let terminal = app.textViews.firstMatch
        print("OCCL>>> [\(stage)] window=\(window)")
        guard terminal.exists else { print("OCCL>>> [\(stage)] no terminal element"); return }
        let t = terminal.frame
        print("OCCL>>> [\(stage)] terminal=\(t) maxY=\(t.maxY)")
        var barTop: CGFloat = .greatestFiniteMagnitude
        for name in ["esc", "ctrl", "meta", "tab"] where app.buttons[name].exists {
            let f = app.buttons[name].frame
            print("OCCL>>> [\(stage)] keybar \(name)=\(f) minY=\(f.minY)")
            barTop = min(barTop, f.minY)
        }
        if barTop < .greatestFiniteMagnitude {
            let overlap = t.maxY - barTop
            print("OCCL>>> [\(stage)] OVERLAP = \(overlap)  (positive means the terminal runs under the bar)")
        }
    }

    private func createHost(_ app: XCUIApplication) throws {
        app.navigationBars.buttons["Add"].tap()
        app.buttons["New Host"].tap()

        let label = app.textFields["Label"]
        XCTAssertTrue(label.waitForExistence(timeout: 5), app.debugDescription)
        label.tap()
        label.typeText("mac")
        let addr = app.textFields["Address"]
        addr.tap()
        addr.typeText("localhost")

        // Create the credentials (username + generated key). The host editor
        // called these "Identity" until the rename to "Credentials".
        app.buttons["New Credentials"].tap()
        let idLabel = app.textFields["Label"]
        XCTAssertTrue(idLabel.waitForExistence(timeout: 5), app.debugDescription)
        idLabel.tap()
        idLabel.typeText("john")
        let user = app.textFields["Username"]
        user.tap()
        user.typeText("john")
        app.segmentedControls.buttons["Key"].tap()
        // The key Picker (menu style) currently reads "None".
        let keyPicker = app.buttons.matching(
            NSPredicate(format: "label CONTAINS 'None' OR value CONTAINS 'None'")).firstMatch
        XCTAssertTrue(keyPicker.waitForExistence(timeout: 5), app.debugDescription)
        keyPicker.tap()
        let verifyKey = app.buttons["verify"]
        XCTAssertTrue(verifyKey.waitForExistence(timeout: 5), app.debugDescription)
        verifyKey.tap()
        app.navigationBars.buttons["Save"].tap()

        // Back in the host editor: pick the identity.
        let idPicker = app.buttons.matching(
            NSPredicate(format: "(label CONTAINS 'Credentials' OR label CONTAINS 'None') AND NOT label CONTAINS 'New'")).firstMatch
        XCTAssertTrue(idPicker.waitForExistence(timeout: 5), app.debugDescription)
        idPicker.tap()
        let johnItem = app.buttons["john"]
        XCTAssertTrue(johnItem.waitForExistence(timeout: 5), app.debugDescription)
        johnItem.tap()
        app.navigationBars.buttons["Save"].tap()
    }

    /// Absolute screen point at the centre of `frame`, for presses that must
    /// not re-resolve an element query.
    private func point(_ app: XCUIApplication, in frame: CGRect) -> XCUICoordinate {
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
    }

    /// SFTP upload and tap-to-act, end to end against the Mac. Needs the
    /// fixture from SKILL.md ("SFTP upload"): ~/pockterm-upload-e2e on the Mac
    /// and zz-upload-{a,b,c}.txt in the simulator's On My iPhone.
    func testSFTPUpload() throws {
        let app = XCUIApplication()
        app.launch()
        try connectToMac(app)
        let browse = app.buttons["Browse Files"]
        XCTAssertTrue(browse.waitForExistence(timeout: 10), app.debugDescription)
        browse.tap()
        XCTAssertTrue(app.navigationBars["mac"].waitForExistence(timeout: 15), app.debugDescription)
        let folder = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'pockterm-upload-e2e'")).firstMatch
        scrollTo(folder, in: app)
        folder.tap()
        let upload = app.buttons["Upload"]
        XCTAssertTrue(upload.waitForExistence(timeout: 10), "no Upload button: \(app.debugDescription)")
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "s1-folder")

        // A tap on a file opens its actions.
        let filler = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'filler-01.txt'")).firstMatch
        XCTAssertTrue(filler.waitForExistence(timeout: 5), app.debugDescription)
        filler.tap()
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5), "tap didn't open file actions")
        XCTAssertTrue(app.buttons["Download"].exists)
        attach(app, name: "s2-file-actions")
        dismissMenu(app)

        // A folder's ⋯ opens the same actions (minus Download).
        app.buttons["Actions"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Rename"].waitForExistence(timeout: 5), "⋯ didn't open folder actions")
        XCTAssertFalse(app.buttons["Download"].exists)
        attach(app, name: "s3-folder-actions")
        dismissMenu(app)

        // What a long press does now, for the record.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'filler-02.txt'")).firstMatch
            .press(forDuration: 1.5)
        Thread.sleep(forTimeInterval: 1)
        print("LONG_PRESS_OPENS_MENU=\(app.buttons["Rename"].exists)")
        attach(app, name: "s4-after-long-press")
        dismissMenu(app)

        // Two files, one clashing: Keep Both.
        pickFiles(["zz-upload-a.txt", "zz-upload-b.txt"], in: app)
        let clash = app.alerts["“zz-upload-a.txt” already exists here"]
        XCTAssertTrue(clash.waitForExistence(timeout: 10), "no clash question: \(app.debugDescription)")
        attach(app, name: "s5-clash")
        clash.buttons["Keep Both"].tap()
        XCTAssertTrue(app.staticTexts["Uploaded 2 files"].waitForExistence(timeout: 20),
                      "no confirmation: \(app.debugDescription)")
        attach(app, name: "s6-uploaded-keep-both")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'zz-upload-b.txt'")).firstMatch.isHittable,
            "listing didn't scroll to the upload")
    }

    /// Stage 2 of the SFTP upload check: Replace, a photo from the library,
    /// and an upload the server refuses (into the read-only folder "ro").
    func testSFTPUploadReplacePhotoFailure() throws {
        let app = XCUIApplication()
        app.launch()
        try connectToMac(app)
        app.buttons["Browse Files"].tap()
        XCTAssertTrue(app.navigationBars["mac"].waitForExistence(timeout: 15), app.debugDescription)
        let folder = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'pockterm-upload-e2e'")).firstMatch
        scrollTo(folder, in: app)
        folder.tap()
        XCTAssertTrue(app.buttons["Upload"].waitForExistence(timeout: 10), app.debugDescription)

        // Replace overwrites, and adds no " 2" copy.
        pickFiles(["zz-upload-c.txt"], in: app)
        let clash = app.alerts["“zz-upload-c.txt” already exists here"]
        XCTAssertTrue(clash.waitForExistence(timeout: 10), "no clash question: \(app.debugDescription)")
        clash.buttons["Replace"].tap()
        XCTAssertTrue(app.staticTexts["Uploaded “zz-upload-c.txt”"].waitForExistence(timeout: 20),
                      "no confirmation: \(app.debugDescription)")
        attach(app, name: "t1-replaced")

        // A photo from the library.
        app.buttons["Upload"].tap()
        let photos = app.buttons["Photos & Videos…"]
        XCTAssertTrue(photos.waitForExistence(timeout: 5), app.debugDescription)
        photos.tap()
        Thread.sleep(forTimeInterval: 3)
        attach(app, name: "t2-photo-picker")
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo'")).firstMatch
        // The picker runs out of process and reports its thumbnails as not
        // hittable, so tap the thumbnail's centre by position.
        if photo.waitForExistence(timeout: 5) {
            photo.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else {
            print("PHOTO_TREE>>>\(app.debugDescription)<<<PHOTO_TREE")
            XCTFail("no photo in picker")
        }
        Thread.sleep(forTimeInterval: 1)
        attach(app, name: "t3-photo-selected")
        // The photo picker's confirm button: identifier "Add", label "Done".
        let confirm = app.buttons.matching(
            NSPredicate(format: "identifier == 'Add' AND label == 'Done'")).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "no picker Done: \(app.debugDescription)")
        confirm.tap()
        let uploadedPhoto = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH 'Uploaded'")).firstMatch
        XCTAssertTrue(uploadedPhoto.waitForExistence(timeout: 30), "photo upload never confirmed: \(app.debugDescription)")
        print("PHOTO_CONFIRMATION=\(uploadedPhoto.label)")
        attach(app, name: "t4-photo-uploaded")

        // The server refuses a write into the read-only folder.
        let ro = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'ro,'")).firstMatch
        scrollUpTo(ro, in: app)
        ro.tap()
        Thread.sleep(forTimeInterval: 2)
        pickFiles(["zz-upload-b.txt"], in: app)
        let failed = app.alerts["Upload Failed"]
        XCTAssertTrue(failed.waitForExistence(timeout: 20), "no failure alert: \(app.debugDescription)")
        attach(app, name: "t5-upload-failed")
        print("FAILURE_TEXT=\(failed.staticTexts.allElementsBoundByIndex.map(\.label))")
        failed.buttons["OK"].tap()
    }

    private func scrollUpTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 where !(element.exists && element.isHittable) {
            app.swipeDown()
        }
        XCTAssertTrue(element.exists && element.isHittable, "never found \(element): \(app.debugDescription)")
    }

    /// Upload → Files… → On My iPhone → the named files → Open.
    private func pickFiles(_ names: [String], in app: XCUIApplication) {
        app.buttons["Upload"].tap()
        let files = app.buttons["Files…"]
        XCTAssertTrue(files.waitForExistence(timeout: 5), app.debugDescription)
        files.tap()
        Thread.sleep(forTimeInterval: 3)
        // The picker shows names without their extensions.
        let stems = names.map { ($0 as NSString).deletingPathExtension }
        let first = app.cells.matching(NSPredicate(format: "label CONTAINS %@", stems[0])).firstMatch
        let onMyPhone = app.cells["DOC.sidebar.item.On My iPhone"]
        if !first.waitForExistence(timeout: 2) {
            // The picker opens wherever it was last: Recents, a folder, or Browse.
            let browseTab = app.tabBars.buttons["Browse"].firstMatch
            if !onMyPhone.exists, browseTab.exists { browseTab.tap(); Thread.sleep(forTimeInterval: 1) }
            let back = app.buttons["Back"]
            if !onMyPhone.exists, back.exists { back.firstMatch.tap(); Thread.sleep(forTimeInterval: 1) }
            XCTAssertTrue(onMyPhone.waitForExistence(timeout: 5), "no On My iPhone: \(app.debugDescription)")
            onMyPhone.tap()
        }
        XCTAssertTrue(first.waitForExistence(timeout: 5), "file not in picker: \(app.debugDescription)")
        attach(app, name: "picker-before-select")
        for stem in stems {
            app.cells.matching(NSPredicate(format: "label CONTAINS %@", stem)).firstMatch.tap()
        }
        attach(app, name: "picker-selected")
        let open = app.buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<20 where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "never found \(element): \(app.debugDescription)")
    }

    /// Closes an open menu by tapping the navigation bar's title area.
    private func dismissMenu(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.08)).tap()
        Thread.sleep(forTimeInterval: 0.7)
    }

    /// Glasses mode. Run on the simulator from scripts/make-glasses-simulator,
    /// which has its external display attached from boot. The host watches
    /// the glasses with `simctl io … --display=external` and reads the size
    /// files this writes on the Mac (the SSH target is the Mac itself).
    /// Unplugging can't be simulated; the no-display path is tested on an
    /// ordinary simulator.
    func testGlassesMode() throws {
        let app = XCUIApplication()
        app.launch()
        try connectToMac(app)

        // Phone: files and keyboard, no terminal, no Files button.
        let sizeMenu = app.buttons["Text Size on Glasses"]
        XCTAssertTrue(sizeMenu.waitForExistence(timeout: 10), "not in glasses mode: \(app.debugDescription)")
        XCTAssertFalse(app.buttons["Browse Files"].exists, "Files button shown in glasses mode")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "no keyboard in glasses mode")
        attach(app, name: "g1-phone-files-and-keyboard")

        // Typing lands in the terminal on the glasses. stty prints "rows cols".
        app.typeText("stty size > /tmp/pockterm-glasses-size\n")
        glassesCheckpoint("typed")

        // Larger glasses text means fewer columns.
        sizeMenu.tap()
        let larger = app.buttons["Larger Text on Glasses"]
        XCTAssertTrue(larger.waitForExistence(timeout: 5), app.debugDescription)
        larger.tap(); larger.tap(); larger.tap()
        // Close the menu with a tap outside it, as a person would. It stays
        // open between taps by design, and an open menu swallows the next
        // keystrokes. The status bar doesn't reach the app; the far-left edge
        // is outside the menu, and a first tap outside a menu only closes it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5)).tap()
        XCTAssertTrue(larger.waitForNonExistence(timeout: 5), "size menu didn't close")
        app.typeText("stty size > /tmp/pockterm-glasses-size-larger\n")
        glassesCheckpoint("larger")

        // Hide the keyboard and bring it back from the top bar.
        app.buttons["Hide Keyboard"].tap()
        let show = app.buttons["Show Keyboard"]
        XCTAssertTrue(show.waitForExistence(timeout: 5), "no Show Keyboard button: \(app.debugDescription)")
        show.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "keyboard didn't come back")
        attach(app, name: "g2-keyboard-back")

        // Review Focus 1: a second session. The glasses follow the switch.
        app.buttons["New Session"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'localhost'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), app.debugDescription)
        row.tap()
        Thread.sleep(forTimeInterval: 4)
        app.typeText("echo SECOND-SESSION; stty size > /tmp/pockterm-glasses-second\n")
        glassesCheckpoint("second-session")

        // Review Focus 5: the shell ends. The phone shows Session Closed.
        app.typeText("exit\n")
        XCTAssertTrue(app.staticTexts["Session Closed"].waitForExistence(timeout: 10),
                      "no Session Closed on the phone: \(app.debugDescription)")
        attach(app, name: "g3-session-closed")
        glassesCheckpoint("closed")
        app.buttons["Close Session"].firstMatch.tap()

        // Minimize: the glasses go idle. Restore: the terminal comes back.
        let minimize = app.buttons["Minimize"]
        XCTAssertTrue(minimize.waitForExistence(timeout: 5), app.debugDescription)
        minimize.tap()
        glassesCheckpoint("minimized")
        let pill = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Resume session'")).firstMatch
        XCTAssertTrue(pill.waitForExistence(timeout: 5), app.debugDescription)
        pill.tap()
        XCTAssertTrue(sizeMenu.waitForExistence(timeout: 5), "didn't restore into glasses mode")
        glassesCheckpoint("restored")

        // Review Focus 4: hardware keys reach the terminal through the proxy.
        // Lines are run with the soft keyboard's return: XCUITest's hardware
        // Return (and its Control modifier) don't reach the terminal even in
        // plain phone mode (measured), and .enter is keypad Enter, which
        // sends ETX and cancels the line.
        app.typeText("echo HW-KEYS\n")
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeText("\n")
        app.typeKey("l", modifierFlags: [])
        app.typeKey("s", modifierFlags: [])
        app.typeText(" /tmp\n")
        glassesCheckpoint("hardware-keys")   // glasses: HW-KEYS twice, then a listing of /tmp

        // Review Focus 2: closing the last session leaves nothing behind.
        app.buttons["Close Session"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["Hosts"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.keyboards.firstMatch.exists, "keyboard left up with no session")
        attach(app, name: "g5-all-closed")
    }

    /// Prints a marker for the host and gives it time to screenshot the glasses.
    private func glassesCheckpoint(_ name: String) {
        print("GLASSES_CHECKPOINT \(name)")
        Thread.sleep(forTimeInterval: 4)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
