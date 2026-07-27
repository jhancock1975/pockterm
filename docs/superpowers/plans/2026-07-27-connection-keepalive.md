# Connection Keep-Alive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let users configure how long an idle SSH session stays connected (per-host, inheriting group → global-default → Off), via an SSH keep-alive that holds idle sessions open then disconnects with a link to the setting.

**Architecture:** Pure catalogs/resolvers (`KeepAliveOption`, `shouldIdleDisconnect`, `resolveKeepAlive`) extend the existing `EffectiveHostSettings` inheritance. `TerminalSession` runs a 60s timer that, while idle, sends a keep-alive (a window-change at the current size — real on-wire SSH traffic via the existing PTY API) and disconnects into a new `.idleDisconnected` state at the hold-time. UI: a Settings→Connection global default, per-host/group pickers, and a disconnect screen linking to the setting.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, Citadel/NIOSSH, swift-testing.

## Global Constraints

- Tests are **pure logic only** — never construct or walk `@Model` in unit tests (SwiftData keypath hangs on the iOS 26.5 simulator). Use plain values.
- Run tests via `scripts/test.sh --build` (recompile) or `scripts/test.sh`. Never plain `xcodebuild test`.
- Test framework is **swift-testing** (`import Testing`, `@Test`, `#expect`).
- Default keep-alive is **Off** (`0` seconds) at every level — reproduces today's behavior (no keep-alive, no client-side close).
- Inherit sentinels: `Host.keepAliveSeconds == 0` = inherit; `HostGroup.defaultKeepAliveSeconds == nil` = not set. A non-optional `@Model Int` **must** carry an inline default (`= 0`) or SwiftData lightweight migration crashes existing users on launch (see `Host.fontSize`).
- Keep-alive interval is a fixed **60s**; only the hold-time is user-configurable.
- Selectable hold-times (seconds): `0` (Off), `300`, `900`, `1800`, `3600`.
- App-target files under `pockterm/` auto-include (PBXFileSystemSynchronizedRootGroup); only test files need pbxproj entries.

---

### Task 1: KeepAlive pure logic (options + idle rule)

**Files:**
- Create: `pockterm/Features/Terminal/KeepAlive.swift`
- Test: `pocktermTests/KeepAliveTests.swift`

**Interfaces:**
- Produces:
  - `struct KeepAliveOption: Identifiable { let seconds: Int; let label: String; var id: Int { seconds } }`
  - `enum KeepAlive { static let interval = 60; static let options: [KeepAliveOption]; static func shouldIdleDisconnect(idleSeconds: Int, holdSeconds: Int) -> Bool; static func label(for seconds: Int) -> String }`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import pockterm

@Test func optionsStartWithOffThenAscend() {
    let secs = KeepAlive.options.map(\.seconds)
    #expect(secs == [0, 300, 900, 1800, 3600])
    #expect(KeepAlive.options.first?.label == "Off")
}

@Test func labelForKnownAndUnknown() {
    #expect(KeepAlive.label(for: 0) == "Off")
    #expect(KeepAlive.label(for: 1800) == "30 min")
    #expect(KeepAlive.label(for: 12345) == "Off")   // unknown → Off
}

@Test func idleDisconnectOffNeverFires() {
    #expect(KeepAlive.shouldIdleDisconnect(idleSeconds: 999999, holdSeconds: 0) == false)
}

@Test func idleDisconnectFiresAtOrAboveHold() {
    #expect(KeepAlive.shouldIdleDisconnect(idleSeconds: 1799, holdSeconds: 1800) == false)
    #expect(KeepAlive.shouldIdleDisconnect(idleSeconds: 1800, holdSeconds: 1800) == true)
    #expect(KeepAlive.shouldIdleDisconnect(idleSeconds: 5000, holdSeconds: 1800) == true)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/test.sh --build`
Expected: FAIL — `KeepAlive` / `KeepAliveOption` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import Foundation

/// One selectable keep-alive hold-time.
struct KeepAliveOption: Identifiable {
    let seconds: Int
    let label: String
    var id: Int { seconds }
}

/// Pure keep-alive policy: the selectable hold-times, the fixed probe
/// interval, and the idle-disconnect rule. No UIKit/SwiftData coupling.
enum KeepAlive {
    /// Seconds between keep-alive probes while a session is idle.
    static let interval = 60

    static let options: [KeepAliveOption] = [
        KeepAliveOption(seconds: 0, label: "Off"),
        KeepAliveOption(seconds: 300, label: "5 min"),
        KeepAliveOption(seconds: 900, label: "15 min"),
        KeepAliveOption(seconds: 1800, label: "30 min"),
        KeepAliveOption(seconds: 3600, label: "60 min"),
    ]

    static func label(for seconds: Int) -> String {
        options.first { $0.seconds == seconds }?.label ?? "Off"
    }

    /// True when an idle session has reached its hold-time and should close.
    /// `holdSeconds == 0` (Off) never disconnects.
    static func shouldIdleDisconnect(idleSeconds: Int, holdSeconds: Int) -> Bool {
        holdSeconds > 0 && idleSeconds >= holdSeconds
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test.sh --build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Features/Terminal/KeepAlive.swift pocktermTests/KeepAliveTests.swift
git commit -m "Add KeepAlive options and idle-disconnect rule"
```

---

### Task 2: resolveKeepAlive in EffectiveHostSettings

**Files:**
- Modify: `pockterm/Vault/EffectiveHostSettings.swift`
- Test: `pocktermTests/EffectiveKeepAliveTests.swift`

**Interfaces:**
- Produces:
  ```swift
  static func resolveKeepAlive(hostValue: Int, chain: [Int?], globalDefault: Int) -> Int
  ```
  Rule: `hostValue` if `!= 0`; else nearest non-nil in `chain`; else `globalDefault` if `!= 0`; else `0`.

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import pockterm

@Test func keepAliveHostValueWins() {
    #expect(EffectiveHostSettings.resolveKeepAlive(
        hostValue: 1800, chain: [900], globalDefault: 300) == 1800)
}

@Test func keepAliveNearestGroupWhenHostInherits() {
    #expect(EffectiveHostSettings.resolveKeepAlive(
        hostValue: 0, chain: [nil, 900], globalDefault: 300) == 900)
}

@Test func keepAliveGlobalWhenHostAndGroupsUnset() {
    #expect(EffectiveHostSettings.resolveKeepAlive(
        hostValue: 0, chain: [nil, nil], globalDefault: 1800) == 1800)
}

@Test func keepAliveOffWhenNothingSet() {
    #expect(EffectiveHostSettings.resolveKeepAlive(
        hostValue: 0, chain: [], globalDefault: 0) == 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/test.sh --build`
Expected: FAIL — `resolveKeepAlive` undefined.

- [ ] **Step 3: Write minimal implementation**

Add to `EffectiveHostSettings` (a pure static, alongside `resolveAppearance`):

```swift
    /// Pure keep-alive inheritance: host value wins (non-zero), else nearest
    /// ancestor group that sets it, else the global default (non-zero), else
    /// Off. `chain` is the host's ancestor groups nearest-first; `0`/`nil`
    /// mean "inherit / not set".
    static func resolveKeepAlive(hostValue: Int, chain: [Int?], globalDefault: Int) -> Int {
        if hostValue != 0 { return hostValue }
        if let group = chain.compactMap({ $0 }).first { return group }
        return globalDefault != 0 ? globalDefault : 0
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test.sh --build`
Expected: PASS; existing tests still green.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Vault/EffectiveHostSettings.swift pocktermTests/EffectiveKeepAliveTests.swift
git commit -m "Add pure keep-alive resolver to EffectiveHostSettings"
```

---

### Task 3: Model fields + ConnectionSettings singleton + resolve(host:) wiring

**Files:**
- Modify: `pockterm/Model/Host.swift`
- Modify: `pockterm/Model/HostGroup.swift`
- Create: `pockterm/Model/ConnectionSettings.swift`
- Modify: `pockterm/Vault/EffectiveHostSettings.swift`

**Interfaces:**
- Consumes: `resolveKeepAlive(...)` (Task 2).
- Produces: `Host.keepAliveSeconds`, `HostGroup.defaultKeepAliveSeconds`, `ConnectionSettings` (singleton), and `@MainActor static func resolveKeepAlive(host:globalDefault:) -> Int`.

No unit test (touches `@Model`); verified by clean build + existing suite.

- [ ] **Step 1: Add Host field**

In `pockterm/Model/Host.swift`, after the existing fields add (inline default required for migration):

```swift
    // Inline default required: SwiftData lightweight migration crashes existing stores without it. 0 = inherit sentinel.
    var keepAliveSeconds: Int = 0
```

Add init param `keepAliveSeconds: Int = 0,` and body `self.keepAliveSeconds = keepAliveSeconds`.

- [ ] **Step 2: Add HostGroup field**

In `pockterm/Model/HostGroup.swift`, after `defaultFontSize`:

```swift
    var defaultKeepAliveSeconds: Int?
```

Add init param `defaultKeepAliveSeconds: Int? = nil,` and body `self.defaultKeepAliveSeconds = defaultKeepAliveSeconds`.

- [ ] **Step 3: Create the ConnectionSettings singleton**

`pockterm/Model/ConnectionSettings.swift` (copy the dedupe pattern from `AISettings.single(in:)`):

```swift
import Foundation
import SwiftData

/// App-wide connection preferences. A single row. `keepAliveSeconds` is the
/// global default hold-time hosts inherit when they and their groups don't
/// set one. `0` = Off (today's behavior).
@Model final class ConnectionSettings {
    // Inline default keeps SwiftData lightweight migration happy.
    var defaultKeepAliveSeconds: Int = 0

    init(defaultKeepAliveSeconds: Int = 0) {
        self.defaultKeepAliveSeconds = defaultKeepAliveSeconds
    }

    /// Returns the single settings row, deduping any accidental extras.
    static func single(in context: ModelContext) -> ConnectionSettings {
        let rows = (try? context.fetch(FetchDescriptor<ConnectionSettings>())) ?? []
        if let first = rows.first {
            for extra in rows.dropFirst() { context.delete(extra) }
            if rows.count > 1 { try? context.save() }
            return first
        }
        let created = ConnectionSettings()
        context.insert(created)
        try? context.save()
        return created
    }
}
```

- [ ] **Step 4: Register the model in the container**

Find where the SwiftData `ModelContainer`/schema lists model types (search: `grep -rn "ModelContainer\|Schema(\|for: \[" pockterm/App`). Add `ConnectionSettings.self` to the schema/model list alongside the others (e.g. `AISettings.self`).

- [ ] **Step 5: Add the @MainActor resolve convenience**

In `EffectiveHostSettings.swift`, add:

```swift
    @MainActor
    static func resolveKeepAlive(host: Host, globalDefault: Int) -> Int {
        var chain: [Int?] = []
        var group = host.group
        while let g = group {
            chain.append(g.defaultKeepAliveSeconds)
            group = g.parent
        }
        return resolveKeepAlive(hostValue: host.keepAliveSeconds, chain: chain,
                                globalDefault: globalDefault)
    }
```

- [ ] **Step 6: Build to verify**

Run: `scripts/test.sh --build`
Expected: BUILD succeeds; existing tests still PASS.

- [ ] **Step 7: Commit**

```bash
git add pockterm/Model/Host.swift pockterm/Model/HostGroup.swift pockterm/Model/ConnectionSettings.swift pockterm/Vault/EffectiveHostSettings.swift pockterm/App
git commit -m "Add keep-alive model fields and ConnectionSettings singleton"
```

---

### Task 4: Keep-alive timer + idle tracking + .idleDisconnected in TerminalSession

**Files:**
- Modify: `pockterm/Features/Terminal/TerminalSession.swift`

**Interfaces:**
- Consumes: `KeepAlive.interval`, `KeepAlive.shouldIdleDisconnect`, `EffectiveHostSettings.resolveKeepAlive(host:globalDefault:)`, `ConnectionSettings.single(in:)`, `engine.resize`.
- Produces: `Status.idleDisconnected`; a keep-alive timer started on connect, torn down on disconnect/close.

No unit test (drives UIKit/timer/actor); verified by build + simulator.

- [ ] **Step 1: Add the status case and idle/size state**

In `enum Status`, add `case idleDisconnected`. Add stored properties:

```swift
    private var lastActivityAt = Date()
    private var lastCols = 80
    private var lastRows = 24
    private var keepAliveTimer: Timer?
    private var holdSeconds = 0
```

- [ ] **Step 2: Track activity and size**

In `handleInput(_:)`, at the top add `lastActivityAt = .now`. Change the `proxy.onSize` closure to record size:

```swift
        proxy.onSize = { [weak self] cols, rows in
            guard let self else { return }
            self.lastCols = cols; self.lastRows = rows
            Task { await self.engine.resize(cols: cols, rows: rows) }
        }
```

- [ ] **Step 3: Start the keep-alive timer after a successful connect**

In `start()`, immediately after `status = .connected`, add:

```swift
            lastActivityAt = .now
            holdSeconds = EffectiveHostSettings.resolveKeepAlive(
                host: host, globalDefault: ConnectionSettings.single(in: modelContext).defaultKeepAliveSeconds)
            startKeepAliveTimer()
```

Add the timer methods:

```swift
    private func startKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        guard holdSeconds > 0 else { return }   // Off = today's behavior
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(KeepAlive.interval),
                                              repeats: true) { [weak self] _ in
            Task { @MainActor in self?.keepAliveTick() }
        }
    }

    private func keepAliveTick() {
        guard status == .connected else { return }
        let idle = Int(Date().timeIntervalSince(lastActivityAt))
        if KeepAlive.shouldIdleDisconnect(idleSeconds: idle, holdSeconds: holdSeconds) {
            keepAliveTimer?.invalidate(); keepAliveTimer = nil
            status = .idleDisconnected
            Task { await engine.disconnect() }
            return
        }
        // Not yet at the limit: emit real SSH traffic (a window-change at the
        // current size) so the server/NAT does not drop the idle session.
        Task { await engine.resize(cols: lastCols, rows: lastRows) }
    }
```

- [ ] **Step 4: Tear the timer down on disconnect**

In `disconnect()`, before `await engine.disconnect()`, add `keepAliveTimer?.invalidate(); keepAliveTimer = nil`. In the `onClose` closure inside `start()`, also invalidate the timer when the shell ends (add `self.keepAliveTimer?.invalidate(); self.keepAliveTimer = nil` next to the status change).

- [ ] **Step 5: Build**

Run: `scripts/test.sh --build`
Expected: BUILD succeeds, tests PASS.

- [ ] **Step 6: Commit**

```bash
git add pockterm/Features/Terminal/TerminalSession.swift
git commit -m "Add idle keep-alive timer and .idleDisconnected state"
```

---

### Task 5: Settings → Connection global-default screen

**Files:**
- Create: `pockterm/Features/Settings/ConnectionSettingsView.swift`
- Modify: `pockterm/App/RootTabView.swift`

**Interfaces:**
- Consumes: `ConnectionSettings.single(in:)`, `KeepAlive.options`.
- Produces: `ConnectionSettingsView`; a "Connection" row in `SettingsHomeView`.

UI task, simulator-verified.

- [ ] **Step 1: Create the settings screen**

```swift
import SwiftUI
import SwiftData

/// App-wide default for how long idle sessions stay connected. Hosts and
/// groups can override this; hosts with no override inherit it.
struct ConnectionSettingsView: View {
    @Environment(\.modelContext) private var ctx
    @State private var seconds = 0

    var body: some View {
        Form {
            Section("Keep sessions alive when idle") {
                Picker("Hold time", selection: $seconds) {
                    ForEach(KeepAlive.options) { opt in
                        Text(opt.label).tag(opt.seconds)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } footer: {
                Text("The default for all hosts. \"Off\" keeps the current behavior. Individual hosts and groups can override this.")
            }
        }
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { seconds = ConnectionSettings.single(in: ctx).defaultKeepAliveSeconds }
        .onChange(of: seconds) { _, new in
            ConnectionSettings.single(in: ctx).defaultKeepAliveSeconds = new
            try? ctx.save()
        }
    }
}
```

- [ ] **Step 2: Add the Connection row to SettingsHomeView**

In `RootTabView.swift`, inside `SettingsHomeView`'s `List`, add a row (after Key Bar):

```swift
                NavigationLink {
                    ConnectionSettingsView()
                } label: {
                    Label("Connection", systemImage: "network")
                }
```

- [ ] **Step 3: Build**

Run: `scripts/test.sh --build`
Expected: BUILD succeeds, tests PASS.

- [ ] **Step 4: Simulator verify**

Run `verify`: open Settings → Connection, pick 30 min, confirm it persists across app relaunch (read `ZCONNECTIONSETTINGS.ZDEFAULTKEEPALIVESECONDS` from the store).

- [ ] **Step 5: Commit**

```bash
git add pockterm/Features/Settings/ConnectionSettingsView.swift pockterm/App/RootTabView.swift
git commit -m "Add Settings → Connection global keep-alive default"
```

---

### Task 6: Host + group editor keep-alive pickers

**Files:**
- Modify: `pockterm/Features/Hosts/HostEditorView.swift`
- Modify: `pockterm/Features/Groups/GroupEditorView.swift`

**Interfaces:**
- Consumes: `KeepAlive.options`; bindings on `Host.keepAliveSeconds` / `HostGroup.defaultKeepAliveSeconds`.

UI task, simulator-verified.

- [ ] **Step 1: Host editor — add to the Connection section**

In `HostEditorView.swift`, inside `Section("Connection")` (after the Port field) add a picker. `Host.keepAliveSeconds` is a non-optional `Int` where `0` already means "inherit", so tag with plain `Int` and label `0` as "Default (inherit)":

```swift
                    Picker("Keep-alive", selection: $host.keepAliveSeconds) {
                        Text("Default (inherit)").tag(0)
                        ForEach(KeepAlive.options.filter { $0.seconds != 0 }) { opt in
                            Text(opt.label).tag(opt.seconds)
                        }
                    }
```

- [ ] **Step 2: Group editor — add to "Defaults inherited by hosts"**

In `GroupEditorView.swift`, inside `Section("Defaults inherited by hosts")` add an optional-tagged picker (matching the existing `Int?`/`String?` idiom):

```swift
                    Picker("Keep-alive", selection: $group.defaultKeepAliveSeconds) {
                        Text("None").tag(Int?.none)
                        ForEach(KeepAlive.options.filter { $0.seconds != 0 }) { opt in
                            Text(opt.label).tag(Int?.some(opt.seconds))
                        }
                    }
```

- [ ] **Step 3: Build**

Run: `scripts/test.sh --build`
Expected: BUILD succeeds, tests PASS.

- [ ] **Step 4: Simulator verify**

Run `verify`: set a host's keep-alive to 5 min, confirm it stores (`ZHOST.ZKEEPALIVESECONDS == 300`); set a group default and confirm a host with "Default (inherit)" resolves to it.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Features/Hosts/HostEditorView.swift pockterm/Features/Groups/GroupEditorView.swift
git commit -m "Add keep-alive pickers to host and group editors"
```

---

### Task 7: Inactivity-disconnect screen with a link to the setting

**Files:**
- Modify: `pockterm/Features/Terminal/SessionTabsView.swift`
- Modify: `pockterm/App/RootTabView.swift`
- Modify: `pockterm/Features/Terminal/SessionManager.swift`

**Interfaces:**
- Consumes: `Status.idleDisconnected`.
- Produces: a `.idleDisconnected` branch in `sessionContent` with a button that dismisses the terminal cover and deep-links to Settings → Connection.

UI/wiring task, simulator-verified.

- [ ] **Step 1: Add a shared deep-link signal**

The terminal cover is presented over the tab view. To route to Settings, add an observable signal. In `SessionManager` (an `@Observable` class), add:

```swift
    /// Set when the user taps "change setting" on the inactivity screen; the
    /// root observes it, closes the terminal, and navigates to Settings.
    var requestOpenConnectionSettings = false
```

- [ ] **Step 2: Render the inactivity screen**

In `SessionTabsView.swift` `sessionContent(_:)`, add a case alongside `.closed`:

```swift
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
```

(Confirm `manager` is in scope in this view; it is the `SessionManager` the view already holds.)

- [ ] **Step 3: Route to Settings in RootTabView**

In `RootTabView`, drive tab selection and a Settings navigation path from the signal. Add `@State private var selectedTab = 0` and `@State private var settingsPath = NavigationPath()`, bind `TabView(selection: $selectedTab)`, tag each tab (`.tag(0)…​.tag(4)` for Settings), give `SettingsHomeView` the path binding, and observe the signal:

```swift
        .onChange(of: sessions.requestOpenConnectionSettings) { _, want in
            guard want else { return }
            selectedTab = 4                       // Settings tab
            settingsPath = NavigationPath()
            settingsPath.append(SettingsRoute.connection)
            sessions.requestOpenConnectionSettings = false
        }
```

Add `enum SettingsRoute { case connection }` and in `SettingsHomeView` accept `@Binding var path: NavigationPath`, wrap its `List` in `NavigationStack(path: $path)`, and add `.navigationDestination(for: SettingsRoute.self) { _ in ConnectionSettingsView() }`. Keep the existing tappable rows working (they can push `SettingsRoute`/views as today).

- [ ] **Step 4: Build**

Run: `scripts/test.sh --build`
Expected: BUILD succeeds, tests PASS.

- [ ] **Step 5: Simulator verify**

Run `verify` with a host set to the shortest hold-time and a lowered `KeepAlive.interval`/hold for the test (or drive via a short hold): let it go idle, confirm the terminal shows the inactivity screen, tap the button, and confirm it lands on Settings → Connection. Also confirm Off (default) never triggers it.

- [ ] **Step 6: Commit**

```bash
git add pockterm/Features/Terminal/SessionTabsView.swift pockterm/App/RootTabView.swift pockterm/Features/Terminal/SessionManager.swift
git commit -m "Add inactivity-disconnect screen linking to Connection settings"
```

---

## Self-Review

**Spec coverage:**
- Data model + resolution (host→group→global→Off) → Tasks 2, 3. ✅
- KeepAlive options + idle rule → Task 1. ✅
- Keep-alive mechanism (on-wire traffic while idle) → Task 4 (window-change at current size via existing `engine.resize`). ✅
- Idle tracking + `.idleDisconnected` → Task 4. ✅
- Settings → Connection global default → Task 5. ✅
- Host/group pickers → Task 6. ✅
- Inactivity screen + deep-link to setting → Task 7. ✅
- Testing (pure resolvers/rule) → Tasks 1, 2. ✅
- Personalize to 30 min for the user: a runtime device setting, not code — done via Settings → Connection (set during verify; user sets on their own device). Called out at handoff, not a task.

**Placeholder scan:** No TBD/TODO; concrete code in every step.

**Type consistency:** `KeepAlive.options`/`.interval`/`.shouldIdleDisconnect`/`.label`, `KeepAliveOption`, `resolveKeepAlive(hostValue:chain:globalDefault:)` and `resolveKeepAlive(host:globalDefault:)`, `ConnectionSettings.single(in:)`/`.defaultKeepAliveSeconds`, `Host.keepAliveSeconds`, `HostGroup.defaultKeepAliveSeconds`, `Status.idleDisconnected`, `SessionManager.requestOpenConnectionSettings`, `SettingsRoute.connection` are used consistently across tasks.

**Keep-alive mechanism note:** a window-change at the current size is real SSH traffic that resets NAT/server idle timers using only Citadel's public PTY API. Tradeoff: full-screen apps (e.g. vim) receive a SIGWINCH (identical size) each idle interval and may redraw — acceptable, only when the user opts into keep-alive, and only while idle. Documented here so the final review treats it as a deliberate choice.
