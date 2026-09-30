# Glasses Display Mode Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When an external display (VITURE glasses, in practice) is attached, the terminal draws full-screen on it, while the phone shows the active session's file browser with the keyboard and key bar typing into that terminal.

**Architecture:** An app-delegate adaptor hands the external-display scene role to a UIKit scene delegate, which hosts `GlassesRootView`. The session's single `TerminalView` moves into that window, and the pty follows its size through the existing `onSize` path. An `ExternalDisplay` registry flips `SessionManager.isGlassesMode`. In that mode `SessionTabsView` swaps the terminal for an embedded `FilesBrowserView` plus an invisible `TerminalKeyboardProxy`, which owns the phone keyboard and forwards all input to the terminal.

**Tech Stack:** Swift 6, SwiftUI with UIKit scenes, SwiftTerm 1.20.0 (`TerminalView`, `UITextInput`), Swift Testing, XCUITest (the verify skill), Device Hub (Xcode 27's simulator app) for a virtual external display.

**Spec:** `docs/superpowers/specs/2026-09-28-glasses-display-mode-design.md`

## Global Constraints

- Deployment target stays iOS 18.0. No new package dependencies.
- **Simulator only. Never drive Hanphone17** with XCUITest, devicectl or anything else (AGENTS.md).
- Unit tests: `scripts/test.sh --build` after source changes. Trust its **exit status**, and never pipe it through `tail`.
- Unit tests use Swift Testing (`import Testing`, `@Test @MainActor`). New tests must not walk SwiftData `@Model` relationships.
- **New test files must be registered:** run `ruby scripts/setup_project.rb` after creating one, because the test target is not a synchronized folder (the app target is). Commit the resulting `pockterm.xcodeproj/project.pbxproj` change with the test. Without it, `scripts/test.sh` silently runs the old test count.
- The verify harness (`add_uitest_target.rb`) hides the `pockterm` scheme. Run `.claude/skills/verify/cleanup.sh` before `scripts/test.sh` or `setup_project.rb`. After a failing UI test `xcodebuild` tends to hang, so cap it with `perl -e 'alarm 300; exec @ARGV' xcodebuild …`.
- Every new user-visible string goes in `pockterm/Localizable.xcstrings` with all 14 translations (ar, el, es, fr, he, hi, it, ja, ko, ru, te, uk, zh-Hans, zh-Hant), and `scripts/i18n-status` must still report full coverage.
- The terminal stays left-to-right in every language (`pinLeftToRightForTerminalContent`).
- Keep pockterm's manual keyboard avoidance. Don't switch to SwiftUI's automatic avoidance: iOS 26 gets the keyboard frame wrong.
- Commits and PRs: John's voice, and **no** Claude/Anthropic trailers, footers or co-author lines.
- Glasses text size: app-wide, default 18pt, clamped to `TerminalZoom.minSize…maxSize` (8–32), stored in UserDefaults under `glassesFontSize`.

## Review Focus

These are the things most likely to bite a real user that no unit test pins. Each one has an end-to-end step in Task 7.

1. **Switching sessions in glasses mode:** the glasses show the newly chosen session's terminal (never blank or stale), typing goes to it, and the file browser switches server.
2. **Closing the last session in glasses mode:** the glasses go to the idle screen, the phone returns to Hosts, the keyboard goes away, and nothing is left holding first responder.
3. **Plugging or unplugging while a sheet or alert is up on the phone** (assistant, theme picker, a file-browser alert): the terminal lands on the right screen and nothing crashes.
4. **A hardware keyboard in glasses mode:** arrows, ctrl and return reach the terminal through the proxy.
5. **The shell ends in glasses mode** (`exit`): the phone shows "Session Closed" with its normal layout, and the glasses show the same status.

## Deviation from the spec

`ExternalDisplay` doesn't store the display's size, although spec section 2 lists `size`. Nothing would read it: the glasses view sizes itself to its window, and the pty follows through `onSize`, including when the display changes mode.

---

### Task 1: Throwaway probe — scene plumbing and "approach C"

This answers two questions before any product code is written:
- Does the app-delegate adaptor get the external-display scene while SwiftUI keeps the main window working?
- Can a view in the external scene become first responder and bring up the **phone** keyboard?

The code lives in the scratch clone, never in the repo.

**Files (all in the scratch clone, thrown away afterwards):**
- Scratch clone: `/private/tmp/claude-501/-Users-john-git-pockterm/dd4bbd43-707b-419a-8896-5ad8f7f6232e/scratchpad/fresh-clone` (already cloned. Run `git -C /private/tmp/claude-501/-Users-john-git-pockterm/dd4bbd43-707b-419a-8896-5ad8f7f6232e/scratchpad/fresh-clone pull --ff-only` first).
- Create: `fresh-clone/pockterm/ProbeGlasses.swift`
- Modify: `fresh-clone/pockterm/pocktermApp.swift` (add one adaptor line)

**Interfaces:**
- Consumes: nothing.
- Produces: a written verdict, recorded in the plan's execution notes and in the memory file `pockterm-glasses-mode.md`:
  - (a) `configurationForConnecting` is called for the external role, and the phone UI still works;
  - (b) the external scene's window shows content;
  - (c) `becomeFirstResponder` in the external scene does or doesn't raise the phone keyboard and receive keys.

- [ ] **Step 1: Write the probe**

`fresh-clone/pockterm/ProbeGlasses.swift`:

```swift
import SwiftUI
import UIKit
import os

let probeLog = Logger(subsystem: "pockterm.probe", category: "glasses")

final class ProbeAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification,
                                               object: nil, queue: .main) { note in
            let frame = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue ?? .zero
            probeLog.log("PROBE keyboardWillShow frame=\(NSCoder.string(for: frame), privacy: .public)")
        }
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        probeLog.log("PROBE configurationForConnecting role=\(session.role.rawValue, privacy: .public)")
        let config = UISceneConfiguration(name: nil, sessionRole: session.role)
        if session.role == .windowExternalDisplayNonInteractive {
            config.delegateClass = ProbeExternalSceneDelegate.self
        }
        return config
    }
}

final class ProbeKeyView: UIView, UIKeyInput {
    private let label = UILabel()
    private var typed = "" { didSet { label.text = "typed: \(typed)" } }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .systemGreen
        label.font = .monospacedSystemFont(ofSize: 48, weight: .bold)
        label.text = "PROBE"
        label.frame = bounds
        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    override var canBecomeFirstResponder: Bool { true }
    var hasText: Bool { !typed.isEmpty }
    func insertText(_ text: String) {
        typed += text
        probeLog.log("PROBE insertText \(text, privacy: .public)")
    }
    func deleteBackward() { _ = typed.popLast() }
}

final class ProbeExternalSceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let key = ProbeKeyView(frame: windowScene.coordinateSpace.bounds)
        key.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let controller = UIViewController()
        controller.view = key
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = controller
        window.isHidden = false
        self.window = window
        probeLog.log("PROBE external connected bounds=\(NSCoder.string(for: windowScene.coordinateSpace.bounds), privacy: .public)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            let ok = key.becomeFirstResponder()
            probeLog.log("PROBE external becomeFirstResponder=\(ok) isFirstResponder=\(key.isFirstResponder)")
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        probeLog.log("PROBE external disconnected")
    }
}
```

In `fresh-clone/pockterm/pocktermApp.swift`, add inside `struct pocktermApp`, above `@State private var container`:

```swift
    @UIApplicationDelegateAdaptor(ProbeAppDelegate.self) private var probeDelegate
```

- [ ] **Step 2: Build, install and launch on the iPhone 18 Pro simulator** (never the phone)

```bash
S=/private/tmp/claude-501/-Users-john-git-pockterm/dd4bbd43-707b-419a-8896-5ad8f7f6232e/scratchpad
U=76FBD4B7-A700-4593-898C-092BE400DE79   # iPhone 18 Pro, iOS 27.0 (xcrun simctl list devices)
cd $S/fresh-clone
xcodebuild build -project pockterm.xcodeproj -scheme pockterm \
  -destination "platform=iOS Simulator,id=$U" -derivedDataPath $S/probe-dd \
  -skipPackagePluginValidation > $S/probe-build.log 2>&1; echo "build exit $?"
xcrun simctl boot $U 2>/dev/null; open -a DeviceHub
xcrun simctl install $U $S/probe-dd/Build/Products/Debug-iphonesimulator/pockterm.app
xcrun simctl spawn $U log stream --style compact \
  --predicate 'subsystem == "pockterm.probe"' > $S/probe.log 2>&1 &
xcrun simctl launch $U John-Hancock.pockterm
```

Expected: `build exit 0`, the app launches to Hosts, and `probe.log` shows `role=UIWindowSceneSessionRoleApplication`.

- [ ] **Step 3: Attach a virtual external display with computer-use in Device Hub**

Call `request_access` for `com.apple.dt.Devices` if it isn't already granted. The screen must be unlocked; if it's locked, stop and report that computer-use can't proceed. Find Device Hub's external-display control (in Xcode ≤ 26 Simulator it was I/O → External Displays → 1920×1080) and pick a 1920×1080 display. **Write down the exact menu path**, because Task 7 documents it in the verify skill. Then:

```bash
xcrun simctl io $U enumerate | grep -B2 -A12 "Display class: 1"   # find the attached external port
cat $S/probe.log
```

Expected in the log: `role=UIWindowSceneSessionRoleExternalDisplayNonInteractive`, `external connected bounds={{0, 0}, {1920, 1080}}` (or similar), and a `becomeFirstResponder=` line two seconds later.

- [ ] **Step 4: Capture both screens and judge approach C**

```bash
xcrun simctl io $U screenshot --display=internal $S/probe-phone.png
xcrun simctl io $U screenshot --display=external $S/probe-glasses.png
```

Read both images. Approach C **works** only if all three hold:
- the log says `becomeFirstResponder=true isFirstResponder=true`
- `probe-phone.png` shows the software keyboard, and `keyboardWillShow` is logged
- tapping a key on the phone keyboard in Device Hub (computer-use click) logs `PROBE insertText` and changes the green screen's text

Otherwise, approach C fails, and Task 5 (the proxy) is required.

- [ ] **Step 5: Record the verdict and clean up**

Write the verdict and the Device Hub menu path into `~/.claude/projects/-Users-john-git-pockterm/memory/pockterm-glasses-mode.md` (new memory, plus a line in `MEMORY.md`). Then:

```bash
pkill -f "log stream --style compact" 2>/dev/null; git -C $S/fresh-clone checkout -- . && git -C $S/fresh-clone clean -fd pockterm
```

Detach the external display in Device Hub. **If approach C works:** drop Task 5, and in Task 6 replace `KeyboardProxyHost` with calling `session.terminalView.becomeFirstResponder()` on the glasses. Everything else stands.

---

### Task 2: Glasses state — `ExternalDisplay`, `GlassesContent`, `GlassesTextSize`

Pure logic, test-first.

**Files:**
- Create: `pockterm/Features/Glasses/ExternalDisplay.swift`
- Create: `pockterm/Features/Glasses/GlassesMode.swift`
- Test: `pocktermTests/ExternalDisplayTests.swift`
- Test: `pocktermTests/GlassesModeTests.swift`

**Interfaces:**
- Consumes: `TerminalZoom.minSize`, `TerminalZoom.maxSize` (8, 32) from `Features/Terminal/TerminalZoom.swift`.
- Produces:
  - `@MainActor @Observable final class ExternalDisplay` with `var isConnected: Bool`, `func isPrimary(_: ObjectIdentifier) -> Bool`, `func attach(_: ObjectIdentifier)`, `func detach(_: ObjectIdentifier)`, `var onConnectionChange: ((Bool) -> Void)?`
  - `enum GlassesContent: Equatable { case idle, terminal(UUID) }` with `static func resolve(isPrimary: Bool, activeID: UUID?, sessionIDs: [UUID], isMinimized: Bool) -> GlassesContent`
  - `enum GlassesTextSize` with `static let defaultSize = 18`, `static let key = "glassesFontSize"`, `static func clamped(_: Int) -> Int`, `static func load(from: UserDefaults) -> Int`, `static func save(_: Int, to: UserDefaults)`

- [ ] **Step 1: Write the failing tests**

`pocktermTests/ExternalDisplayTests.swift`:

```swift
import Testing
import Foundation
@testable import pockterm

/// Scene stand-ins. Held for the whole test: an ObjectIdentifier of a
/// deallocated object can be handed out again.
@MainActor
private final class Scenes {
    let a = NSObject(), b = NSObject()
    var idA: ObjectIdentifier { ObjectIdentifier(a) }
    var idB: ObjectIdentifier { ObjectIdentifier(b) }
}

@Test @MainActor func noDisplayMeansNotConnected() {
    let display = ExternalDisplay()
    #expect(!display.isConnected)
}

@Test @MainActor func theFirstDisplayConnectsAndShowsTheTerminal() {
    let scenes = Scenes(), display = ExternalDisplay()
    var changes: [Bool] = []
    display.onConnectionChange = { changes.append($0) }
    display.attach(scenes.idA)
    #expect(display.isConnected)
    #expect(display.isPrimary(scenes.idA))
    #expect(changes == [true])
}

@Test @MainActor func aSecondDisplayIsIdleAndChangesNothing() {
    let scenes = Scenes(), display = ExternalDisplay()
    var changes: [Bool] = []
    display.onConnectionChange = { changes.append($0) }
    display.attach(scenes.idA)
    display.attach(scenes.idB)
    #expect(!display.isPrimary(scenes.idB))
    #expect(changes == [true])
}

@Test @MainActor func losingThePrimaryHandsTheTerminalToTheNext() {
    let scenes = Scenes(), display = ExternalDisplay()
    display.attach(scenes.idA)
    display.attach(scenes.idB)
    display.detach(scenes.idA)
    #expect(display.isConnected)
    #expect(display.isPrimary(scenes.idB))
}

@Test @MainActor func losingTheLastDisplayDisconnects() {
    let scenes = Scenes(), display = ExternalDisplay()
    var changes: [Bool] = []
    display.onConnectionChange = { changes.append($0) }
    display.attach(scenes.idA)
    display.detach(scenes.idA)
    #expect(!display.isConnected)
    #expect(changes == [true, false])
}

@Test @MainActor func repeatsAndStrangersAreIgnored() {
    let scenes = Scenes(), display = ExternalDisplay()
    var changes: [Bool] = []
    display.onConnectionChange = { changes.append($0) }
    display.attach(scenes.idA)
    display.attach(scenes.idA)
    display.detach(scenes.idB)
    #expect(display.isConnected)
    #expect(changes == [true])
}
```

`pocktermTests/GlassesModeTests.swift`:

```swift
import Testing
import Foundation
@testable import pockterm

private let one = UUID(), two = UUID()

@Test @MainActor func noSessionsShowsTheIdleScreen() {
    #expect(GlassesContent.resolve(isPrimary: true, activeID: nil, sessionIDs: [],
                                   isMinimized: false) == .idle)
}

@Test @MainActor func anOpenSessionShowsItsTerminal() {
    #expect(GlassesContent.resolve(isPrimary: true, activeID: two, sessionIDs: [one, two],
                                   isMinimized: false) == .terminal(two))
}

@Test @MainActor func minimizingShowsTheIdleScreen() {
    #expect(GlassesContent.resolve(isPrimary: true, activeID: one, sessionIDs: [one],
                                   isMinimized: true) == .idle)
}

@Test @MainActor func anActiveIDWithNoSessionShowsTheIdleScreen() {
    // Mid-close: activeID can briefly name a session that is already gone.
    #expect(GlassesContent.resolve(isPrimary: true, activeID: two, sessionIDs: [one],
                                   isMinimized: false) == .idle)
}

@Test @MainActor func aSecondDisplayOnlyEverShowsTheIdleScreen() {
    #expect(GlassesContent.resolve(isPrimary: false, activeID: one, sessionIDs: [one],
                                   isMinimized: false) == .idle)
}

/// A private defaults domain per test, removed afterwards.
@MainActor
private func withDefaults(_ body: (UserDefaults) -> Void) {
    let name = "glasses-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    body(defaults)
    defaults.removePersistentDomain(forName: name)
}

@Test @MainActor func glassesTextStartsAt18() {
    withDefaults { #expect(GlassesTextSize.load(from: $0) == 18) }
}

@Test @MainActor func glassesTextSizeRoundTrips() {
    withDefaults { defaults in
        GlassesTextSize.save(22, to: defaults)
        #expect(GlassesTextSize.load(from: defaults) == 22)
    }
}

@Test @MainActor func glassesTextSizeIsClampedBothWays() {
    withDefaults { defaults in
        GlassesTextSize.save(4, to: defaults)
        #expect(GlassesTextSize.load(from: defaults) == TerminalZoom.minSize)
        defaults.set(99, forKey: GlassesTextSize.key)   // a value from outside the app
        #expect(GlassesTextSize.load(from: defaults) == TerminalZoom.maxSize)
    }
}
```

- [ ] **Step 2: Run the tests and confirm they fail to compile**

Run: `scripts/test.sh --build; echo "exit $?"`
Expected: `BUILD FAILED` naming `ExternalDisplay`, `GlassesContent` and `GlassesTextSize`, and a non-zero exit.

- [ ] **Step 3: Implement**

`pockterm/Features/Glasses/ExternalDisplay.swift`:

```swift
import Foundation
import Observation

/// The external screens iOS has handed the app: video glasses, a TV or a
/// monitor (iOS can't tell them apart). The first one attached shows the
/// terminal and any others show the idle screen. Scene delegates register
/// here, and everything that behaves differently in glasses mode keys off
/// `isConnected`.
@MainActor
@Observable
final class ExternalDisplay {
    private var scenes: [ObjectIdentifier] = []

    /// Called when the first display arrives (true) and when the last one
    /// leaves (false). AppContainer points this at the session manager.
    @ObservationIgnored var onConnectionChange: ((Bool) -> Void)?

    var isConnected: Bool { !scenes.isEmpty }

    /// Whether this scene is the one that shows the terminal.
    func isPrimary(_ scene: ObjectIdentifier) -> Bool { scenes.first == scene }

    func attach(_ scene: ObjectIdentifier) {
        guard !scenes.contains(scene) else { return }
        let wasConnected = isConnected
        scenes.append(scene)
        if !wasConnected { onConnectionChange?(true) }
    }

    func detach(_ scene: ObjectIdentifier) {
        guard let index = scenes.firstIndex(of: scene) else { return }
        scenes.remove(at: index)
        if !isConnected { onConnectionChange?(false) }
    }
}
```

`pockterm/Features/Glasses/GlassesMode.swift`:

```swift
import Foundation

/// What the glasses show. One pure rule, so it can be tested without a
/// display attached.
enum GlassesContent: Equatable {
    case idle
    case terminal(UUID)

    /// The terminal appears on the primary display exactly when it would be on
    /// the phone's screen: a live session, not minimized. Everything else (no
    /// sessions, minimized, a second display) gets the idle screen.
    static func resolve(isPrimary: Bool, activeID: UUID?, sessionIDs: [UUID],
                        isMinimized: Bool) -> GlassesContent {
        guard isPrimary, !isMinimized, let activeID, sessionIDs.contains(activeID) else {
            return .idle
        }
        return .terminal(activeID)
    }
}

/// The terminal's text size on the glasses. It's one app-wide value, kept
/// apart from the phone's pinch zoom because the two screens want very
/// different sizes. 18pt on a 1920×1080 display gives about 178×50.
enum GlassesTextSize {
    static let defaultSize = 18
    static let key = "glassesFontSize"

    static func clamped(_ size: Int) -> Int {
        min(TerminalZoom.maxSize, max(TerminalZoom.minSize, size))
    }

    static func load(from defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: key)   // 0 when never set
        return stored == 0 ? defaultSize : clamped(stored)
    }

    static func save(_ size: Int, to defaults: UserDefaults = .standard) {
        defaults.set(clamped(size), forKey: key)
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `scripts/test.sh --build; echo "exit $?"`
Expected: `exit 0`, with the 14 new tests among the passes.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Features/Glasses pocktermTests/ExternalDisplayTests.swift pocktermTests/GlassesModeTests.swift
git commit -m "Track external displays and decide what the glasses show"
```

---

### Task 3: Glasses mode in the session manager and sessions

**Files:**
- Modify: `pockterm/Features/Terminal/TerminalSession.swift` (new properties after `baselineFontSize`; `applyAppearance()`'s size line)
- Modify: `pockterm/Features/Terminal/SessionManager.swift` (init, `open`, new members)
- Modify: `pockterm/App/AppContainer.swift`
- Modify: `pockterm/pocktermApp.swift`
- Test: `pocktermTests/GlassesModeTests.swift` (append)

**Interfaces:**
- Consumes: `GlassesTextSize`, `ExternalDisplay` (Task 2).
- Produces:
  - `TerminalSession.isGlassesMode: Bool` (read-only), `TerminalSession.displayedFontSize: Int`, `TerminalSession.setGlassesMode(_ on: Bool, fontSize: Int)`
  - `SessionManager.init(secretStore:modelContext:defaults: UserDefaults = .standard)`, `SessionManager.isGlassesMode: Bool` (read-only), `SessionManager.glassesFontSize: Int` (read-only), `SessionManager.setGlassesMode(_: Bool)`, `SessionManager.setGlassesFontSize(_: Int)`
  - `AppContainer.shared`, `AppContainer.display: ExternalDisplay`

- [ ] **Step 1: Write the failing tests**

Add `import SwiftData` to the imports at the top of `pocktermTests/GlassesModeTests.swift`, then append:

```swift
/// A manager with one session attached directly (no SSH), and its own
/// defaults domain so the glasses size never touches the real one.
@MainActor
private struct GlassesFixture {
    let container: ModelContainer   // a ModelContext doesn't retain its container
    let manager: SessionManager
    let session: TerminalSession
    let defaults: UserDefaults
    let suite = "glasses-fixture-\(UUID().uuidString)"

    init() throws {
        container = try ModelContainer(
            for: Host.self, Identity.self, SSHKeyRecord.self, KnownHostRecord.self,
            HostGroup.self, Snippet.self, CommandHistory.self,
            configurations: .init(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let host = Host(label: "web", address: "10.0.0.1")
        ctx.insert(host)
        defaults = UserDefaults(suiteName: suite)!
        manager = SessionManager(secretStore: InMemorySecretStore(), modelContext: ctx,
                                 defaults: defaults)
        session = TerminalSession(host: host, secretStore: manager.secretStore, modelContext: ctx)
        manager.sessions = [session]
        manager.activeID = session.id
    }

    func tearDown() { defaults.removePersistentDomain(forName: suite) }
}

@Test @MainActor func glassesModeDrawsEverySessionAtTheGlassesSize() throws {
    let f = try GlassesFixture(); defer { f.tearDown() }
    f.manager.setGlassesMode(true)
    #expect(f.session.isGlassesMode)
    #expect(f.session.displayedFontSize == GlassesTextSize.defaultSize)
}

@Test @MainActor func leavingGlassesModeRestoresThePhoneZoom() throws {
    let f = try GlassesFixture(); defer { f.tearDown() }
    f.session.currentFontSize = 11
    f.manager.setGlassesMode(true)
    f.manager.setGlassesMode(false)
    #expect(!f.session.isGlassesMode)
    #expect(f.session.displayedFontSize == 11)
}

@Test @MainActor func glassesTextChangesApplyLiveAndAreRemembered() throws {
    let f = try GlassesFixture(); defer { f.tearDown() }
    f.manager.setGlassesMode(true)
    f.manager.setGlassesFontSize(24)
    #expect(f.session.displayedFontSize == 24)
    #expect(GlassesTextSize.load(from: f.defaults) == 24)
}

@Test @MainActor func glassesTextIsClampedAtTheManager() throws {
    let f = try GlassesFixture(); defer { f.tearDown() }
    f.manager.setGlassesFontSize(40)
    #expect(f.manager.glassesFontSize == TerminalZoom.maxSize)
}

@Test @MainActor func glassesTextChangesLeaveThePhoneAloneOutsideGlassesMode() throws {
    let f = try GlassesFixture(); defer { f.tearDown() }
    let phoneSize = f.session.displayedFontSize
    f.manager.setGlassesFontSize(26)
    #expect(f.session.displayedFontSize == phoneSize)
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `scripts/test.sh --build; echo "exit $?"`
Expected: `BUILD FAILED` (the `defaults:` argument and the glasses members don't exist yet).

- [ ] **Step 3: Implement the session side**

In `TerminalSession.swift`, add after `let baselineFontSize: Int`:

```swift
    /// True while this session's terminal is on the glasses. The text size
    /// then comes from `glassesFontSize` instead of the phone's zoom.
    private(set) var isGlassesMode = false
    private(set) var glassesFontSize = GlassesTextSize.defaultSize

    /// The size the terminal is drawn at right now.
    var displayedFontSize: Int { isGlassesMode ? glassesFontSize : currentFontSize }

    /// Moves this session in or out of glasses mode, or changes the glasses
    /// size. Leaving hands caret focus-tracking back to the terminal itself,
    /// which TerminalKeyboardProxy turns off while it holds the keyboard.
    func setGlassesMode(_ on: Bool, fontSize: Int) {
        guard on != isGlassesMode || fontSize != glassesFontSize else { return }
        isGlassesMode = on
        glassesFontSize = fontSize
        if !on { terminalView.caretViewTracksFocus = true }
        applyAppearance()
    }
```

In `applyAppearance()`, replace `let size = CGFloat(currentFontSize)` with:

```swift
        let size = CGFloat(displayedFontSize)
```

- [ ] **Step 4: Implement the manager side**

In `SessionManager.swift`, add below `let modelContext: ModelContext`:

```swift
    /// True while an external display is attached: the terminal draws there,
    /// and the phone shows files and the keyboard. Set from ExternalDisplay
    /// by AppContainer.
    private(set) var isGlassesMode = false
    /// The terminal's text size on the glasses, shared by every session.
    private(set) var glassesFontSize: Int
    private let defaults: UserDefaults
```

Replace the `init` with:

```swift
    init(secretStore: SecretStore, modelContext: ModelContext,
         defaults: UserDefaults = .standard) {
        self.secretStore = secretStore
        self.modelContext = modelContext
        self.defaults = defaults
        self.glassesFontSize = GlassesTextSize.load(from: defaults)
    }
```

In `open(_:)`, after `session.sessionManager = self`, add:

```swift
        if isGlassesMode { session.setGlassesMode(true, fontSize: glassesFontSize) }
```

Add these methods after `closeAll()`:

```swift
    func setGlassesMode(_ on: Bool) {
        isGlassesMode = on
        for session in sessions { session.setGlassesMode(on, fontSize: glassesFontSize) }
    }

    func setGlassesFontSize(_ size: Int) {
        let clamped = GlassesTextSize.clamped(size)
        guard clamped != glassesFontSize else { return }
        glassesFontSize = clamped
        GlassesTextSize.save(clamped, to: defaults)
        guard isGlassesMode else { return }
        for session in sessions { session.setGlassesMode(true, fontSize: clamped) }
    }
```

- [ ] **Step 5: Make the container shared and wire the display**

`pockterm/App/AppContainer.swift`. Replace the class with:

```swift
/// Owns the app-wide SwiftData container and the production secret store.
@MainActor
final class AppContainer {
    /// The one container. The app and the glasses scene delegate both reach
    /// it here: UIKit creates the scene delegate, not SwiftUI, so the App's
    /// state can't be handed to it.
    static let shared = AppContainer()

    let modelContainer: ModelContainer
    let secretStore: SecretStore
    let sessions: SessionManager
    let forwards: ForwardRunner
    let modelRefresher: ModelCatalogRefresher
    let display = ExternalDisplay()

    private init() {
        let container = try! ModelContainer(
            for: Host.self, Identity.self, SSHKeyRecord.self, KnownHostRecord.self,
            HostGroup.self, Snippet.self, PortForward.self, CommandHistory.self,
            AISettings.self, ConnectionSettings.self, AssistantMessageRecord.self)
        let store = KeychainSecretStore()
        modelContainer = container
        secretStore = store
        sessions = SessionManager(secretStore: store, modelContext: container.mainContext)
        forwards = ForwardRunner(secretStore: store, modelContext: container.mainContext)
        modelRefresher = ModelCatalogRefresher(secretStore: store)
        display.onConnectionChange = { [sessions] connected in
            sessions.setGlassesMode(connected)
        }
    }
}
```

In `pockterm/pocktermApp.swift`, replace `@State private var container = AppContainer()` with:

```swift
    private let container = AppContainer.shared
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `scripts/test.sh --build; echo "exit $?"`
Expected: `exit 0`, including the 5 new glasses-mode tests and every existing `SessionManagerTests` test (their `SessionManager(secretStore:modelContext:)` calls still compile through the defaulted parameter).

- [ ] **Step 7: Commit**

```bash
git add pockterm/Features/Terminal/TerminalSession.swift pockterm/Features/Terminal/SessionManager.swift \
        pockterm/App/AppContainer.swift pockterm/pocktermApp.swift pocktermTests/GlassesModeTests.swift
git commit -m "Give sessions a glasses mode with its own remembered text size"
```

---

### Task 4: The glasses scene — the terminal on the external display

**Files:**
- Create: `pockterm/App/AppDelegate.swift`
- Create: `pockterm/Features/Glasses/ExternalDisplaySceneDelegate.swift`
- Create: `pockterm/Features/Glasses/GlassesRootView.swift`
- Create: `pockterm/Features/Terminal/SessionStatusView.swift`
- Modify: `pockterm/pocktermApp.swift` (adaptor)
- Modify: `pockterm/Features/Terminal/SessionTabsView.swift` (`TerminalHostView`; `sessionContent` status switch; the glasses-mode placeholder in `body`)

**Interfaces:**
- Consumes: `AppContainer.shared`, `.display`, `.sessions` (Task 3); `GlassesContent.resolve`, `ExternalDisplay.attach/detach/isPrimary` (Task 2); `SessionManager.isGlassesMode`, `.isMinimized`, `.activeID`, `.sessions`.
- Produces:
  - `TerminalHostView(terminalView: TerminalView, avoidsKeyboard: Bool = true)`, which re-adopts its terminal view whenever SwiftUI updates it
  - `SessionStatusView(session: TerminalSession, manager: SessionManager)`
  - `GlassesRootView(manager:display:sceneID:)`
  - `AppDelegate`

- [ ] **Step 1: Extract the status overlay into `SessionStatusView`**

`pockterm/Features/Terminal/SessionStatusView.swift`. This is the `switch session.status` block moved verbatim from `SessionTabsView.sessionContent`:

```swift
import SwiftUI

/// What a session shows when it isn't simply connected: connecting, failed,
/// closed, or dropped for inactivity. It sits over the terminal on the phone
/// and on the glasses, and replaces the file browser in glasses mode.
struct SessionStatusView: View {
    let session: TerminalSession
    let manager: SessionManager

    var body: some View {
        switch session.status {
        case .connecting:
            ProgressView("Connecting…").controlSize(.large).tint(.white)
        case .failed(let message):
            ContentUnavailableView("Connection Failed", systemImage: "xmark.octagon",
                                   description: Text(message))
                .foregroundStyle(.white)
        case .closed:
            ContentUnavailableView("Session Closed", systemImage: "bolt.horizontal",
                                   description: Text("The remote shell ended."))
                .foregroundStyle(.white)
        case .idleDisconnected:
            ContentUnavailableView {
                Label("Disconnected due to inactivity", systemImage: "moon.zzz")
            } description: {
                Text("This session was closed after being idle. You can change how long sessions stay connected.")
            } actions: {
                Button("Change how long sessions stay connected") {
                    manager.requestOpenConnectionSettings = true
                    manager.minimize()   // dismiss the full-screen terminal cover
                }
            }
            .foregroundStyle(.white)
        case .connected:
            EmptyView()
        }
    }
}
```

In `SessionTabsView.sessionContent(_:)`, replace the whole `switch session.status { … }` block with:

```swift
            SessionStatusView(session: session, manager: manager)
```

- [ ] **Step 2: Make `TerminalHostView` re-adopt its terminal**

Replace `struct TerminalHostView` in `SessionTabsView.swift` with:

```swift
/// Hosts an existing `TerminalView` (owned by a session) inside SwiftUI.
/// Keyboard avoidance is done in UIKit via `keyboardLayoutGuide`, which stays
/// correct across rotations where SwiftUI's automatic avoidance leaves the
/// terminal's bottom rows behind the accessory bar.
///
/// A view lives in one window at a time, and the same terminal moves between
/// the phone and the glasses. So every update makes sure this container holds
/// exactly the terminal it was given. That covers plugging in, unplugging and
/// switching sessions, without either side knowing about the other.
struct TerminalHostView: UIViewRepresentable {
    let terminalView: TerminalView
    /// Off on the glasses, where there's no keyboard to make room for.
    var avoidsKeyboard = true

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        adopt(into: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if terminalView.superview !== uiView { adopt(into: uiView) }
        // Subviews SwiftTerm adds after makeUIView (its own scroller and
        // accessory views) would otherwise inherit the mirrored default.
        uiView.pinLeftToRightForTerminalContent()
    }

    private func adopt(into container: UIView) {
        for case let stale as TerminalView in container.subviews where stale !== terminalView {
            stale.removeFromSuperview()
        }
        terminalView.removeFromSuperview()
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminalView)
        let bottom = avoidsKeyboard ? container.keyboardLayoutGuide.topAnchor : container.bottomAnchor
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: container.topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottom),
        ])
        // In Hebrew and Arabic the rest of the app mirrors, but the terminal
        // must not: the server addresses columns from the left. See
        // Localization/LeftToRight.swift. This also keeps the leading/trailing
        // constraints above resolving to left/right.
        container.pinLeftToRightForTerminalContent()
    }
}
```

- [ ] **Step 3: Keep the phone off the terminal in glasses mode (placeholder until Task 6)**

In `SessionTabsView.body`, replace

```swift
                if let session = manager.active {
                    sessionContent(session)
                } else {
```

with

```swift
                if let session = manager.active {
                    if manager.isGlassesMode {
                        Color.black   // replaced by GlassesPhoneContent in Task 6
                    } else {
                        sessionContent(session)
                    }
                } else {
```

- [ ] **Step 4: The app delegate and the scene delegate**

`pockterm/App/AppDelegate.swift`:

```swift
import UIKit

/// Hands external displays to `ExternalDisplaySceneDelegate`, and every other
/// scene back to SwiftUI. Without this, iOS mirrors the phone onto the glasses.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let role = connectingSceneSession.role
        let config = UISceneConfiguration(name: nil, sessionRole: role)
        if role == .windowExternalDisplayNonInteractive {
            config.delegateClass = ExternalDisplaySceneDelegate.self
        }
        return config
    }
}
```

`pockterm/Features/Glasses/ExternalDisplaySceneDelegate.swift`:

```swift
import SwiftUI
import UIKit

/// Owns the window iOS gives the app on an external display. It registers
/// with `ExternalDisplay` while connected and shows `GlassesRootView`.
@MainActor
final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let container = AppContainer.shared
        let id = ObjectIdentifier(windowScene)
        let host = UIHostingController(rootView: GlassesRootView(
            manager: container.sessions, display: container.display, sceneID: id))
        host.view.backgroundColor = .black
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = host
        window.isHidden = false
        self.window = window
        container.display.attach(id)
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        AppContainer.shared.display.detach(ObjectIdentifier(scene))
        window = nil
    }
}
```

In `pockterm/pocktermApp.swift`, add above `private let container = AppContainer.shared`:

```swift
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
```

- [ ] **Step 5: `GlassesRootView`**

`pockterm/Features/Glasses/GlassesRootView.swift`:

```swift
import SwiftUI

/// Everything the glasses show: the active session's terminal, full screen
/// and nothing else, or an idle screen when there's no terminal to show.
struct GlassesRootView: View {
    let manager: SessionManager
    let display: ExternalDisplay
    let sceneID: ObjectIdentifier

    var body: some View {
        ZStack {
            Color.black
            switch content {
            case .terminal(let id):
                if let session = manager.sessions.first(where: { $0.id == id }) {
                    ZStack {
                        TerminalHostView(terminalView: session.terminalView, avoidsKeyboard: false)
                        // Display-only here: its buttons are live on the phone.
                        SessionStatusView(session: session, manager: manager)
                            .environment(\.dynamicTypeSize, .accessibility2)
                            .allowsHitTesting(false)
                    }
                }
            case .idle:
                GlassesIdleView()
            }
        }
        .ignoresSafeArea()
    }

    private var content: GlassesContent {
        GlassesContent.resolve(isPrimary: display.isPrimary(sceneID),
                               activeID: manager.activeID,
                               sessionIDs: manager.sessions.map(\.id),
                               isMinimized: manager.isMinimized)
    }
}

/// The Pockterm mark (the same `>_` tile as pockterm.com) and one line saying
/// where to go next.
private struct GlassesIdleView: View {
    private static let tile = Color(red: 0.04, green: 0.07, blue: 0.13)
    private static let green = Color(red: 0.25, green: 0.82, blue: 0.50)

    var body: some View {
        VStack(spacing: 32) {
            RoundedRectangle(cornerRadius: 36)
                .fill(Self.tile)
                .frame(width: 160, height: 160)
                .overlay(Text(verbatim: ">_")
                    .font(.system(size: 76, weight: .bold, design: .monospaced))
                    .foregroundStyle(Self.green))
            Text("Open a session on your phone")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
```

- [ ] **Step 6: Build and run the unit tests**

Run: `scripts/test.sh --build; echo "exit $?"`
Expected: `exit 0`. Nothing new is unit-tested here, but the refactors must keep every test green.

- [ ] **Step 7: Simulator smoke test with computer-use and simctl** (iPhone 18 Pro sim, never the phone)

1. Build and install the app for the simulator, the same as in Task 1 Step 2 but from `/Users/john/git/pockterm` with its own `-derivedDataPath`. Launch it.
2. Confirm the phone shows Hosts normally: `xcrun simctl io $U screenshot --display=internal`.
3. Attach the 1920×1080 external display in Device Hub, using the path recorded in Task 1. Screenshot `--display=external` and confirm the idle screen shows ">_" and "Open a session on your phone".
4. In Device Hub, create a host for `john@localhost:22`, reusing the verify skill's key if the app container already has one (see `.claude/skills/verify/SKILL.md`, phase 1). Add a snippet named `size` with the command `stty size > /tmp/pockterm-glasses-size`. Open the session and accept the host key.
5. Screenshot `--display=external`. Expected: the shell prompt full screen, with no tab bar and no buttons. The phone shows its top bar over black.
6. Run the `size` snippet from the phone's snippet menu, then `cat /tmp/pockterm-glasses-size` on the Mac. Expected: rows and columns on the order of 50 and 178, far above the phone's (about 40 × 46).
7. Minimize, and confirm the glasses show the idle screen. Restore, and confirm the terminal is back.
8. Detach the display. The phone must show the terminal again. Run the snippet again, and `/tmp/pockterm-glasses-size` must now hold the phone's size.

Any failure goes back into this task's code before committing.

- [ ] **Step 8: Commit**

```bash
git add pockterm/App/AppDelegate.swift pockterm/Features/Glasses pockterm/Features/Terminal/SessionStatusView.swift \
        pockterm/Features/Terminal/SessionTabsView.swift pockterm/pocktermApp.swift
git commit -m "Draw the terminal on an external display, with an idle screen when there's no session"
```

---

### Task 5: `TerminalKeyboardProxy` — the phone keyboard for a terminal on the glasses

Skip this task if Task 1 found that approach C works.

**Files:**
- Create: `pockterm/Features/Glasses/TerminalKeyboardProxy.swift`
- Modify: `pockterm/Features/Terminal/KeyBarView.swift` (`hideKeyboard()`)
- Test: `pocktermTests/TerminalKeyboardProxyTests.swift`

**Interfaces:**
- Consumes: SwiftTerm `TerminalView` (`insertText`, `deleteBackward`, the `UITextInput` members, `inputAccessoryView`, `caretViewTracksFocus`, `getTerminal().setTerminalFocus(_:)`).
- Produces:
  - `final class TerminalKeyboardProxy: UIView, UITextInput` with `var target: TerminalView?`, `var onFocusChange: ((Bool) -> Void)?` and `func requestFocus()`
  - `struct KeyboardProxyHost: UIViewRepresentable` with `init(terminalView: TerminalView, focusRequest: Int, onFocusChange: @escaping (Bool) -> Void)`

- [ ] **Step 1: Write the failing tests**

`pocktermTests/TerminalKeyboardProxyTests.swift`:

```swift
import Testing
import UIKit
import SwiftTerm
@testable import pockterm

/// Collects what the terminal would send to the server. Not @MainActor, the
/// same as the app's TerminalDelegateProxy: SwiftTerm's delegate protocol
/// isn't actor-isolated.
private final class Capture: NSObject, TerminalViewDelegate {
    var bytes: [UInt8] = []
    func send(source: TerminalView, data: ArraySlice<UInt8>) { bytes += data }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func scrolled(source: TerminalView, position: Double) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

/// Records which object the system was told changed.
@MainActor
private final class DelegateSpy: NSObject, UITextInputDelegate {
    var senders: [AnyObject?] = []
    func selectionWillChange(_ textInput: UITextInput?) { senders.append(textInput as AnyObject?) }
    func selectionDidChange(_ textInput: UITextInput?) { senders.append(textInput as AnyObject?) }
    func textWillChange(_ textInput: UITextInput?) { senders.append(textInput as AnyObject?) }
    func textDidChange(_ textInput: UITextInput?) { senders.append(textInput as AnyObject?) }
}

@MainActor
private func terminal() -> (TerminalView, Capture) {
    let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    let capture = Capture()
    view.terminalDelegate = capture
    return (view, capture)
}

@MainActor
private func proxy(for view: TerminalView) -> TerminalKeyboardProxy {
    let proxy = TerminalKeyboardProxy(frame: .zero)
    proxy.target = view
    return proxy
}

@Test @MainActor func typedTextReachesTheServer() {
    let (view, capture) = terminal()
    proxy(for: view).insertText("ls -la")
    #expect(capture.bytes == Array("ls -la".utf8))
}

@Test @MainActor func backspaceWithNothingBufferedSendsDEL() {
    let (view, capture) = terminal()
    proxy(for: view).deleteBackward()
    #expect(capture.bytes == [0x7f])
}

@Test @MainActor func aJapaneseCompositionSendsNothingUntilItCommits() {
    let (view, capture) = terminal()
    let proxy = proxy(for: view)
    proxy.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0))
    proxy.setMarkedText("日本", selectedRange: NSRange(location: 2, length: 0))
    #expect(capture.bytes.isEmpty)
    #expect(proxy.markedTextRange != nil)
    proxy.unmarkText()
    #expect(capture.bytes == Array("日本".utf8))
}

@Test @MainActor func theKeyBarTravelsWithTheTarget() {
    let (view, _) = terminal()
    let bar = UIView()
    view.inputAccessoryView = bar
    #expect(proxy(for: view).inputAccessoryView === bar)
}

@Test @MainActor func switchingTargetsSendsTypingToTheNewTerminal() {
    let (first, firstCapture) = terminal()
    let (second, secondCapture) = terminal()
    let proxy = proxy(for: first)
    proxy.target = second
    proxy.insertText("x")
    #expect(firstCapture.bytes.isEmpty)
    #expect(secondCapture.bytes == Array("x".utf8))
}

@Test @MainActor func theSystemHearsTerminalChangesAsComingFromTheProxy() {
    // The system only listens to its first responder, which is the proxy, so
    // the terminal's own change notifications have to arrive under its name.
    let (view, _) = terminal()
    let proxy = proxy(for: view)
    let spy = DelegateSpy()
    proxy.inputDelegate = spy
    view.inputDelegate?.textWillChange(view)
    #expect(spy.senders.count == 1)
    #expect(spy.senders.first! === proxy)
}

@Test @MainActor func withoutATargetTheProxyRefusesTheKeyboard() {
    #expect(!TerminalKeyboardProxy(frame: .zero).canBecomeFirstResponder)
}
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `scripts/test.sh --build; echo "exit $?"`
Expected: `BUILD FAILED` (`TerminalKeyboardProxy` is undefined).

- [ ] **Step 3: Implement the proxy**

`pockterm/Features/Glasses/TerminalKeyboardProxy.swift`:

```swift
import SwiftUI
import UIKit
import SwiftTerm

/// The phone's keyboard, for a terminal that's drawn on the glasses.
///
/// iPhone external displays are display-only: a view there can't bring up the
/// keyboard. So in glasses mode this invisible view on the phone is first
/// responder instead. It carries the session's key bar and forwards every
/// piece of input (typed text, Backspace, CJK composition, hardware keys) to
/// the terminal. SwiftTerm's input methods don't check whether the terminal
/// itself is first responder, which is what makes forwarding enough.
final class TerminalKeyboardProxy: UIView, UITextInput {
    /// Where typing goes. Changing it hands focus over and swaps in the new
    /// session's key bar.
    var target: TerminalView? {
        didSet {
            guard target !== oldValue else { return }
            if let oldValue {
                if isFirstResponder { release(oldValue) }
                if oldValue.inputDelegate === relay { oldValue.inputDelegate = nil }
            }
            target?.inputDelegate = relay
            if isFirstResponder, let target { claim(target) }
            reloadInputViews()
        }
    }

    /// Told whenever the keyboard comes or goes, so the phone can offer a way
    /// to bring it back.
    var onFocusChange: ((Bool) -> Void)?

    private let relay = InputDelegateRelay()
    private var wantsFocus = false
    private var focusAttempts = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        relay.proxy = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Focus

    /// Takes the keyboard now if it can, or as soon as it's in a window and
    /// nothing is animating over it. An alert that's still animating away
    /// refuses to give up first responder.
    func requestFocus() {
        wantsFocus = true
        focusAttempts = 0
        attemptFocus()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attemptFocus()
    }

    private func attemptFocus() {
        guard wantsFocus, window != nil, target != nil else { return }
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        if let transition = top?.transitionCoordinator {
            transition.animate(alongsideTransition: nil) { [weak self] _ in self?.attemptFocus() }
            return
        }
        if becomeFirstResponder() {
            wantsFocus = false
        } else if focusAttempts < 5 {
            focusAttempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.attemptFocus() }
        }
    }

    override var canBecomeFirstResponder: Bool { target != nil }

    override var inputAccessoryView: UIView? { target?.inputAccessoryView }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        if let target { claim(target) }
        onFocusChange?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        if let target { release(target) }
        onFocusChange?(false)
        return true
    }

    /// While the keyboard is held for it, the terminal behaves as focused: the
    /// caret blinks, and apps that ask (tmux, vim) get their focus-in event.
    private func claim(_ terminal: TerminalView) {
        terminal.caretViewTracksFocus = false
        terminal.getTerminal().setTerminalFocus(true)
    }

    private func release(_ terminal: TerminalView) {
        terminal.caretViewTracksFocus = true
        terminal.getTerminal().setTerminalFocus(false)
    }

    // MARK: Hardware keyboard

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let target else { return super.pressesBegan(presses, with: event) }
        target.pressesBegan(presses, with: event)
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let target else { return super.pressesChanged(presses, with: event) }
        target.pressesChanged(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let target else { return super.pressesEnded(presses, with: event) }
        target.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let target else { return super.pressesCancelled(presses, with: event) }
        target.pressesCancelled(presses, with: event)
    }

    // MARK: UITextInputTraits: the terminal's own, so the keyboard is identical

    var keyboardType: UIKeyboardType { target?.keyboardType ?? .default }
    var keyboardAppearance: UIKeyboardAppearance { target?.keyboardAppearance ?? .default }
    var returnKeyType: UIReturnKeyType { target?.returnKeyType ?? .default }
    var autocapitalizationType: UITextAutocapitalizationType { target?.autocapitalizationType ?? .none }
    var autocorrectionType: UITextAutocorrectionType { target?.autocorrectionType ?? .no }
    var spellCheckingType: UITextSpellCheckingType { target?.spellCheckingType ?? .no }
    var smartQuotesType: UITextSmartQuotesType { target?.smartQuotesType ?? .no }
    var smartDashesType: UITextSmartDashesType { target?.smartDashesType ?? .no }
    var smartInsertDeleteType: UITextSmartInsertDeleteType { target?.smartInsertDeleteType ?? .no }

    // MARK: UIKeyInput

    var hasText: Bool { target?.hasText ?? false }
    func insertText(_ text: String) { target?.insertText(text) }
    func deleteBackward() { target?.deleteBackward() }

    // MARK: UITextInput: text and positions, all the terminal's

    func text(in range: UITextRange) -> String? { target?.text(in: range) }
    func replace(_ range: UITextRange, withText text: String) { target?.replace(range, withText: text) }

    var selectedTextRange: UITextRange? {
        get { target?.selectedTextRange }
        set { target?.selectedTextRange = newValue }
    }
    var markedTextRange: UITextRange? { target?.markedTextRange }
    var markedTextStyle: [NSAttributedString.Key: Any]? {
        get { target?.markedTextStyle }
        set { target?.markedTextStyle = newValue }
    }
    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        target?.setMarkedText(markedText, selectedRange: selectedRange)
    }
    func unmarkText() { target?.unmarkText() }

    var beginningOfDocument: UITextPosition { target?.beginningOfDocument ?? UITextPosition() }
    var endOfDocument: UITextPosition { target?.endOfDocument ?? UITextPosition() }

    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        target?.textRange(from: fromPosition, to: toPosition)
    }
    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        target?.position(from: position, offset: offset)
    }
    func position(from position: UITextPosition, in direction: UITextLayoutDirection,
                  offset: Int) -> UITextPosition? {
        target?.position(from: position, in: direction, offset: offset)
    }
    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        target?.compare(position, to: other) ?? .orderedSame
    }
    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        target?.offset(from: from, to: toPosition) ?? 0
    }
    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        target?.position(within: range, farthestIn: direction)
    }
    func characterRange(byExtending position: UITextPosition,
                        in direction: UITextLayoutDirection) -> UITextRange? {
        target?.characterRange(byExtending: position, in: direction)
    }

    var inputDelegate: UITextInputDelegate? {
        get { relay.system }
        set { relay.system = newValue }
    }

    lazy var tokenizer: UITextInputTokenizer = UITextInputStringTokenizer(textInput: self)

    func baseWritingDirection(for position: UITextPosition,
                              in direction: UITextStorageDirection) -> NSWritingDirection { .leftToRight }
    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}

    // MARK: UITextInput geometry
    //
    // The terminal is on another screen, so rectangles in its coordinates mean
    // nothing here. Anything the system anchors to text (the candidate bar,
    // the loupe) anchors to this view instead.

    func firstRect(for range: UITextRange) -> CGRect { bounds }
    func caretRect(for position: UITextPosition) -> CGRect {
        CGRect(x: 0, y: 0, width: 1, height: max(bounds.height, 1))
    }
    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }
    func closestPosition(to point: CGPoint) -> UITextPosition? { nil }
    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? { nil }
    func characterRange(at point: CGPoint) -> UITextRange? { nil }
}

/// Sits between the terminal and the system's text-input machinery. The
/// terminal announces changes with itself as the sender, but the system only
/// listens to its first responder, the proxy. So each notification is re-sent
/// as coming from the proxy.
private final class InputDelegateRelay: NSObject, UITextInputDelegate {
    weak var proxy: TerminalKeyboardProxy?
    weak var system: UITextInputDelegate?

    func selectionWillChange(_ textInput: UITextInput?) { system?.selectionWillChange(proxy) }
    func selectionDidChange(_ textInput: UITextInput?) { system?.selectionDidChange(proxy) }
    func textWillChange(_ textInput: UITextInput?) { system?.textWillChange(proxy) }
    func textDidChange(_ textInput: UITextInput?) { system?.textDidChange(proxy) }
}

/// Puts a `TerminalKeyboardProxy` in the SwiftUI tree. Changing
/// `focusRequest` asks for the keyboard.
struct KeyboardProxyHost: UIViewRepresentable {
    let terminalView: TerminalView
    let focusRequest: Int
    let onFocusChange: (Bool) -> Void

    final class Coordinator { var handledRequest: Int? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TerminalKeyboardProxy {
        TerminalKeyboardProxy(frame: .zero)
    }

    func updateUIView(_ proxy: TerminalKeyboardProxy, context: Context) {
        proxy.onFocusChange = onFocusChange
        proxy.target = terminalView
        if context.coordinator.handledRequest != focusRequest {
            context.coordinator.handledRequest = focusRequest
            proxy.requestFocus()
        }
    }

    static func dismantleUIView(_ proxy: TerminalKeyboardProxy, coordinator: Coordinator) {
        // Silently: this runs mid-update, when state changes aren't allowed,
        // and on unplug the phone still needs to know the keyboard was up.
        proxy.onFocusChange = nil
        _ = proxy.resignFirstResponder()
        proxy.target = nil
    }
}
```

- [ ] **Step 4: Make the key bar's hide key work for whoever shows it**

In `KeyBarView.swift`, replace `hideKeyboard()` with:

```swift
    @objc private func hideKeyboard() {
        UIDevice.current.playInputClick()
        // Whoever is showing this bar owns the keyboard: the terminal on the
        // phone, or TerminalKeyboardProxy in glasses mode.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `scripts/test.sh --build; echo "exit $?"`
Expected: `exit 0`, including the 7 new proxy tests.

- [ ] **Step 6: Commit**

```bash
git add pockterm/Features/Glasses/TerminalKeyboardProxy.swift pockterm/Features/Terminal/KeyBarView.swift \
        pocktermTests/TerminalKeyboardProxyTests.swift
git commit -m "Forward the phone keyboard to a terminal drawn on another screen"
```

---

### Task 6: The phone in glasses mode — files, keyboard, controls, translations

**Files:**
- Create: `pockterm/Features/Glasses/GlassesPhoneContent.swift`
- Modify: `pockterm/Features/Files/FilesBrowserView.swift` (init, toolbar, text-entry callback). Since PR #5 the browser has a bottom Upload capsule in a `safeAreaInset`, and it opens file actions on a tap. In glasses mode that capsule sits above the keyboard padding and needs no change. Check it in the Step 6 smoke test.
- Modify: `pockterm/Features/Terminal/SessionTabsView.swift` (state, content switch, top bar, unplug handoff)
- Modify: `pockterm/Localizable.xcstrings` (5 new keys)

**Interfaces:**
- Consumes: `KeyboardProxyHost` (Task 5), `SessionStatusView` (Task 4), `SessionManager.isGlassesMode`, `.glassesFontSize`, `.setGlassesFontSize(_:)` (Task 3), `TerminalZoom.minSize/maxSize`.
- Produces:
  - `FilesBrowserView(host:secretStore:modelContext:embedded: Bool = false, onTextEntryEnded: (() -> Void)? = nil)`
  - `GlassesPhoneContent(session:manager:focusRequest:keyboardUp:)`
  - The accessibility labels Task 7's driver relies on: "Text Size on Glasses", "Smaller Text on Glasses", "Larger Text on Glasses" and "Show Keyboard".

- [ ] **Step 1: Let the file browser live embedded**

In `FilesBrowserView.swift`, add after `@State private var showingHelp = false`:

```swift
    /// Shown in place of the terminal in glasses mode rather than as a sheet.
    /// There's nothing to go back to there, so Done is hidden.
    private let embedded: Bool
    /// Called when one of the browser's text boxes (new folder, rename,
    /// permissions) closes, so glasses mode can give the keyboard back to the
    /// terminal.
    private let onTextEntryEnded: (() -> Void)?
```

Replace the `init` with:

```swift
    init(host: Host, secretStore: SecretStore, modelContext: ModelContext,
         embedded: Bool = false, onTextEntryEnded: (() -> Void)? = nil) {
        _model = State(initialValue: FilesBrowserModel(host: host, secretStore: secretStore,
                                                       modelContext: modelContext))
        self.embedded = embedded
        self.onTextEntryEnded = onTextEntryEnded
    }
```

After the `.modifier(FilesBrowserAlerts(…))` call inside the `NavigationStack`, add:

```swift
            .onChange(of: textEntryOpen) { _, open in
                if !open { onTextEntryEnded?() }
            }
```

Add this property to `FilesBrowserView`:

```swift
    private var textEntryOpen: Bool {
        showingNewFolder || renameTarget != nil || chmodTarget != nil
    }
```

In `toolbarContent`, wrap the Done item:

```swift
        if !embedded {
            ToolbarItem(placement: .topBarLeading) {
                Button("Done") { dismiss() }
            }
        }
```

- [ ] **Step 2: `GlassesPhoneContent`**

`pockterm/Features/Glasses/GlassesPhoneContent.swift`:

```swift
import SwiftUI

/// The phone's content area in glasses mode: the active session's files where
/// the terminal would be, and the keyboard typing into the terminal on the
/// glasses. While the session isn't connected, it shows the session's status
/// instead, with its buttons live.
///
/// Keyboard avoidance is manual, the same way AssistantView does it: iOS 26's
/// automatic avoidance uses a keyboard frame that leaves out the predictive
/// bar. SessionTabsView's root already ignores the keyboard safe area.
struct GlassesPhoneContent: View {
    let session: TerminalSession
    let manager: SessionManager
    /// Bumped by the top bar's Show Keyboard button.
    let focusRequest: Int
    @Binding var keyboardUp: Bool

    /// Bumped here when a file-browser text box closes.
    @State private var textEntryRefocus = 0
    @State private var containerBottom: CGFloat = 0
    @State private var keyboardTop: CGFloat = .infinity

    private var keyboardOverlap: CGFloat { max(0, containerBottom - keyboardTop) }

    var body: some View {
        ZStack {
            KeyboardProxyHost(terminalView: session.terminalView,
                              focusRequest: focusRequest &+ textEntryRefocus,
                              onFocusChange: { keyboardUp = $0 })
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if session.status == .connected {
                FilesBrowserView(host: session.host, secretStore: session.secretStore,
                                 modelContext: session.modelContext, embedded: true,
                                 onTextEntryEnded: { textEntryRefocus &+= 1 })
                    .id(session.id)
                    .environment(\.colorScheme, .dark)
                    .padding(.bottom, keyboardOverlap)
                    .animation(.easeOut(duration: 0.2), value: keyboardOverlap)
            } else {
                SessionStatusView(session: session, manager: manager)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(keyboardOverlapReader)
    }

    private var keyboardOverlapReader: some View {
        GeometryReader { geo in
            let bottom = geo.frame(in: .global).maxY
            Color.clear
                .onAppear { containerBottom = bottom }
                .onChange(of: bottom) { containerBottom = bottom }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                    guard let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                                     as? NSValue)?.cgRectValue else { return }
                    keyboardTop = end.minY
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillHideNotification)) { _ in
                    keyboardTop = .infinity
                }
        }
    }
}
```

- [ ] **Step 3: Wire it into `SessionTabsView`**

Add to `SessionTabsView`'s state:

```swift
    @State private var glassesKeyboardUp = false
    @State private var glassesFocusRequest = 0
```

Replace Task 4's placeholder `Color.black   // replaced by GlassesPhoneContent in Task 6` with:

```swift
                        GlassesPhoneContent(session: session, manager: manager,
                                            focusRequest: glassesFocusRequest,
                                            keyboardUp: $glassesKeyboardUp)
```

After `.ignoresSafeArea(.keyboard)` in `body`, add:

```swift
        // Unplugged while typing: the terminal is back on the phone, so it gets
        // the keyboard directly rather than waiting for a tap.
        .onChange(of: manager.isGlassesMode) { _, glasses in
            guard !glasses, glassesKeyboardUp, let session = manager.active else { return }
            glassesKeyboardUp = false
            DispatchQueue.main.async { _ = session.terminalView.becomeFirstResponder() }
        }
```

In `topBar`, change the Files button's condition from `if let session = manager.active {` to:

```swift
                    if let session = manager.active, !manager.isGlassesMode {
```

and add right after that Files button block:

```swift
                    if manager.isGlassesMode {
                        glassesControls
                    }
```

Add to `SessionTabsView`:

```swift
    /// Glasses mode's stand-ins for what the terminal's surface does on the
    /// phone: text size (there's no pinching the glasses), and a way to bring
    /// the keyboard back (there's no terminal on the phone to tap). The size
    /// menu stays open between taps so it can step several sizes at once.
    @ViewBuilder
    private var glassesControls: some View {
        Menu {
            ControlGroup {
                Button {
                    manager.setGlassesFontSize(manager.glassesFontSize - 1)
                } label: {
                    Label("Smaller Text on Glasses", systemImage: "textformat.size.smaller")
                }
                .disabled(manager.glassesFontSize <= TerminalZoom.minSize)
                Button {
                    manager.setGlassesFontSize(manager.glassesFontSize + 1)
                } label: {
                    Label("Larger Text on Glasses", systemImage: "textformat.size.larger")
                }
                .disabled(manager.glassesFontSize >= TerminalZoom.maxSize)
            }
            .menuActionDismissBehavior(.disabled)
        } label: {
            Image(systemName: "textformat.size")
        }
        .accessibilityLabel("Text Size on Glasses")
        if !glassesKeyboardUp, manager.active != nil {
            Button { glassesFocusRequest &+= 1 } label: {
                Image(systemName: "keyboard")
            }
            .accessibilityLabel("Show Keyboard")
        }
    }
```

- [ ] **Step 4: Add the five strings with all 14 translations**

Run this once from the repo root. It inserts the keys in the catalog's code-point order and writes the file back in Xcode's own format (2-space indent, `": "`, trailing newline):

```bash
python3 - <<'EOF'
import json
path = "pockterm/Localizable.xcstrings"
T = {
 "Open a session on your phone": {
  "ar": "افتح جلسة على هاتفك", "el": "Ανοίξτε μια συνεδρία στο τηλέφωνό σας",
  "es": "Abre una sesión en tu teléfono", "fr": "Ouvrez une session sur votre téléphone",
  "he": "פתח הפעלה בטלפון", "hi": "अपने फ़ोन पर एक सत्र खोलें",
  "it": "Apri una sessione sul telefono", "ja": "iPhone でセッションを開いてください",
  "ko": "iPhone에서 세션을 여세요", "ru": "Откройте сессию на телефоне",
  "te": "మీ ఫోన్‌లో ఒక సెషన్ తెరవండి", "uk": "Відкрийте сесію на телефоні",
  "zh-Hans": "请在 iPhone 上打开一个会话", "zh-Hant": "請在 iPhone 上開啟一個工作階段"},
 "Show Keyboard": {
  "ar": "إظهار لوحة المفاتيح", "el": "Εμφάνιση πληκτρολογίου", "es": "Mostrar el teclado",
  "fr": "Afficher le clavier", "he": "הצג מקלדת", "hi": "कीबोर्ड दिखाएँ",
  "it": "Mostra tastiera", "ja": "キーボードを表示", "ko": "키보드 보기",
  "ru": "Показать клавиатуру", "te": "కీబోర్డ్ చూపించు", "uk": "Показати клавіатуру",
  "zh-Hans": "显示键盘", "zh-Hant": "顯示鍵盤"},
 "Text Size on Glasses": {
  "ar": "حجم النص على النظارة", "el": "Μέγεθος κειμένου στα γυαλιά",
  "es": "Tamaño del texto en las gafas", "fr": "Taille du texte sur les lunettes",
  "he": "גודל הטקסט במשקפיים", "hi": "चश्मे पर टेक्स्ट का आकार",
  "it": "Dimensione del testo sugli occhiali", "ja": "メガネの文字サイズ",
  "ko": "안경 텍스트 크기", "ru": "Размер текста на очках",
  "te": "కళ్లద్దాలపై అక్షరాల పరిమాణం", "uk": "Розмір тексту в окулярах",
  "zh-Hans": "眼镜上的文字大小", "zh-Hant": "眼鏡上的文字大小"},
 "Smaller Text on Glasses": {
  "ar": "تصغير النص على النظارة", "el": "Μικρότερο κείμενο στα γυαλιά",
  "es": "Reducir el texto en las gafas", "fr": "Réduire le texte sur les lunettes",
  "he": "הקטן טקסט במשקפיים", "hi": "चश्मे पर टेक्स्ट छोटा करें",
  "it": "Riduci il testo sugli occhiali", "ja": "メガネの文字を小さく",
  "ko": "안경 텍스트 작게", "ru": "Уменьшить текст на очках",
  "te": "కళ్లద్దాలపై అక్షరాలను చిన్నవిగా చేయి", "uk": "Зменшити текст в окулярах",
  "zh-Hans": "缩小眼镜上的文字", "zh-Hant": "縮小眼鏡上的文字"},
 "Larger Text on Glasses": {
  "ar": "تكبير النص على النظارة", "el": "Μεγαλύτερο κείμενο στα γυαλιά",
  "es": "Ampliar el texto en las gafas", "fr": "Agrandir le texte sur les lunettes",
  "he": "הגדל טקסט במשקפיים", "hi": "चश्मे पर टेक्स्ट बड़ा करें",
  "it": "Ingrandisci il testo sugli occhiali", "ja": "メガネの文字を大きく",
  "ko": "안경 텍스트 크게", "ru": "Увеличить текст на очках",
  "te": "కళ్లద్దాలపై అక్షరాలను పెద్దవిగా చేయి", "uk": "Збільшити текст в окулярах",
  "zh-Hans": "放大眼镜上的文字", "zh-Hant": "放大眼鏡上的文字"},
}
d = json.load(open(path))
for key, langs in T.items():
    assert key not in d["strings"], key
    d["strings"][key] = {"localizations": {
        lang: {"stringUnit": {"state": "translated", "value": value}}
        for lang, value in sorted(langs.items())}}
d["strings"] = dict(sorted(d["strings"].items()))
open(path, "w").write(json.dumps(d, indent=2, ensure_ascii=False, separators=(",", ": ")) + "\n")
EOF
git diff --stat pockterm/Localizable.xcstrings
scripts/i18n-status; echo "exit $?"
```

Expected: the diff touches only additions (about 350 lines), and `i18n-status` reports every language at full coverage with no specifier or emphasis errors (`exit 0`).

- [ ] **Step 5: Build and run the unit tests**

Run: `scripts/test.sh --build; echo "exit $?"`
Expected: `exit 0`.

- [ ] **Step 6: Simulator smoke test** (iPhone 18 Pro sim, display attached in Device Hub)

1. Open the localhost session with the display attached. Phone screenshot: the top bar (without the Files button, with the text-size button), the file browser listing `~` in dark style, and the keyboard with the key bar below it. Glasses screenshot: the terminal.
2. Tap keys on the phone keyboard in Device Hub (computer-use), e.g. `echo hi` then return. The glasses show `hi`.
3. The key bar's hide key hides the keyboard, and **Show Keyboard** appears in the top bar. Tapping it brings the keyboard back.
4. Rename a file in the browser and cancel. The keyboard returns, still typing into the terminal (`echo back` shows on the glasses).
5. Text size: open the menu, tap Larger twice, and the glasses text visibly grows. Check `stty size` through the snippet: fewer columns than before.
6. Detach the display while the keyboard is up. The phone shows the terminal with the keyboard up, and typing goes straight in.

- [ ] **Step 7: Commit**

```bash
git add pockterm/Features/Glasses/GlassesPhoneContent.swift pockterm/Features/Files/FilesBrowserView.swift \
        pockterm/Features/Terminal/SessionTabsView.swift pockterm/Localizable.xcstrings
git commit -m "In glasses mode, show files on the phone with the keyboard typing into the glasses"
```

---

### Task 7: End-to-end verification in the simulator, including the Review Focus cases

**Files:**
- Modify: `.claude/skills/verify/uitests/VerifyDriverUITests.swift` (add `testGlassesMode` and a helper)
- Modify: `.claude/skills/verify/SKILL.md` (a "Glasses mode" section: Device Hub display path, run order, host-side checks)

**Interfaces:**
- Consumes: the labels "Text Size on Glasses", "Larger Text on Glasses", "Show Keyboard", "Minimize", "New Session", "Close Session" and "Hide Keyboard" (the key bar's dismiss chip, `KeyBarKey.hideKeyboard.displayName`); the verify skill's `connectToMac`, `createHost` and `attach` helpers.
- Produces: evidence, namely phone screenshots from the xcresult, glasses screenshots from `simctl io`, and size files on the Mac.

- [ ] **Step 1: Add the driver phase**

Append inside `VerifyDriverUITests`, before the final `attach` helper:

```swift
    /// Glasses mode. Run with a virtual external display ALREADY attached in
    /// Device Hub; the test can't attach one. The host watches the glasses
    /// with `simctl io … --display=external` and reads the size files this
    /// writes on the Mac (the SSH target is the Mac itself). At
    /// GLASSES_CHECKPOINT unplug, detach the display in Device Hub. The test
    /// waits up to 90 s for the terminal to come back to the phone.
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
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3)).tap()   // close the menu
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

        // Unplug: the terminal returns to the phone and takes typing directly.
        glassesCheckpoint("unplug")
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline, sizeMenu.exists { Thread.sleep(forTimeInterval: 1) }
        XCTAssertFalse(sizeMenu.exists, "still in glasses mode after unplug")
        XCTAssertTrue(app.buttons["Browse Files"].waitForExistence(timeout: 5), app.debugDescription)
        app.typeText("stty size > /tmp/pockterm-phone-size\n")
        Thread.sleep(forTimeInterval: 2)
        attach(app, name: "g4-back-on-phone")

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
```

- [ ] **Step 2: Install the driver and run the phase**

Follow `.claude/skills/verify/SKILL.md`: `add_uitest_target.rb`, `add_scheme.rb`, build-for-testing with destination `platform=iOS Simulator,id=76FBD4B7-A700-4593-898C-092BE400DE79`, run phase 1 if the app has no key, and authorize the key. Attach the external display in Device Hub. Then:

```bash
S=/private/tmp/claude-501/-Users-john-git-pockterm/dd4bbd43-707b-419a-8896-5ad8f7f6232e/scratchpad; U=76FBD4B7-A700-4593-898C-092BE400DE79
rm -f /tmp/pockterm-glasses-size* /tmp/pockterm-glasses-second /tmp/pockterm-phone-size
( i=0; while :; do xcrun simctl io $U screenshot --display=external $S/glasses-$i.png >/dev/null 2>&1; i=$((i+1)); perl -e 'select(undef,undef,undef,1)'; done ) &
echo $! > $S/shots.pid
xcodebuild test-without-building -project pockterm.xcodeproj -scheme pocktermUI \
  -destination "platform=iOS Simulator,id=$U" \
  -only-testing:pocktermUITests/VerifyDriverUITests/testGlassesMode \
  -resultBundlePath $S/glasses.xcresult 2>&1 | tee $S/glasses-test.log | grep --line-buffered GLASSES_CHECKPOINT
```

When `GLASSES_CHECKPOINT unplug` prints, detach the display in Device Hub with computer-use. Afterwards, stop the screenshot loop (`kill $(cat $S/shots.pid)`) and export the phone shots with `xcrun xcresulttool export attachments --path $S/glasses.xcresult --output-path $S/glasses-shots`.

- [ ] **Step 3: Check the evidence**

- `xcodebuild` exits 0 and the test passed.
- `/tmp/pockterm-glasses-size` holds glasses-scale numbers (rows and cols far above the phone's). `-larger` has fewer columns. `-second` matches the first file's size (same display, same font). `/tmp/pockterm-phone-size` has phone-scale numbers.
- Glasses frames: the terminal full screen at "typed" and "larger" (visibly bigger text), `SECOND-SESSION` at "second-session", the Session Closed status at "closed", the idle screen at "minimized", and the terminal again at "restored".
- Phone shots g1–g5 match the assertions. In g1 the file list sits above the keyboard and key bar, not behind them.

- [ ] **Step 4: tmux on the glasses against `tmux capture-pane`**

With the display attached, open a session and type `tmux -L g new -A -s g` on the phone keyboard. From the Mac, run `tmux -L g send-keys -t g 'top' Enter`, wait 3 s, and screenshot `--display=external`. Compare it row by row with `tmux -L g capture-pane -p -t g`. Every row must agree, and the status line must be on the last row. Then run `tmux -L g kill-server`.

- [ ] **Step 5: Review Focus 3 and 4 by hand** (computer-use in Device Hub)

- Open the AI assistant sheet on the phone, then detach and re-attach the display. The app doesn't crash, the sheet is still up, and after dismissing it the terminal is on the glasses and typing works.
- Turn on Device Hub's hardware keyboard setting and type `ls` followed by up-arrow and return on the Mac keyboard into the simulator window. The glasses show `ls` run, then recalled and run again.

- [ ] **Step 6: Tear the driver down and document it**

Run `.claude/skills/verify/cleanup.sh` (it reverts the temporary target and scheme). Add a "Glasses mode" section to `.claude/skills/verify/SKILL.md` covering:
- the Device Hub external-display path recorded in Task 1
- that `testGlassesMode` needs the display attached first
- the screenshot loop and the checkpoint/unplug protocol
- the host-side files it writes

Confirm `git status` shows only `SKILL.md` and `VerifyDriverUITests.swift` changed under `.claude/`.

- [ ] **Step 7: Commit**

```bash
git add .claude/skills/verify/SKILL.md .claude/skills/verify/uitests/VerifyDriverUITests.swift
git commit -m "Verify glasses mode end to end against the Mac's sshd"
```

---

### Task 8: Ship

**Files:** none new.

- [ ] **Step 1: Full unit run from a clean build**

Run: `scripts/test.sh --build; echo "exit $?"`
Expected: `exit 0`. Record the pass count for the PR.

- [ ] **Step 2: Push, open the PR and merge** (AGENTS.md: ship finished work unprompted)

```bash
git push -u origin glasses-display-mode
gh pr create --title "Glasses display mode: terminal on the glasses, files and keyboard on the phone" --body "<why; what changed; what was measured: unit count, the stty sizes on glasses/larger/phone, tmux capture-pane match, Review Focus results>"
gh pr merge <n> --squash --delete-branch
git checkout main && git pull --ff-only && git status
```

No Claude attribution anywhere in the PR. Expected: `git status` clean, and `main` in sync.

- [ ] **Step 3: Record what future sessions need**

Update `~/.claude/projects/-Users-john-git-pockterm/memory/pockterm-glasses-mode.md` with:
- the approach-C verdict and the Device Hub path
- where the pieces live (`Features/Glasses/`)
- the rule that the phone never hosts the terminal in glasses mode
- anything that surprised us

Keep its `MEMORY.md` line current.
