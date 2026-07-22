# Terminal Appearance Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add per-host terminal theme, font, and pinch-to-zoom to pockterm, inheriting through the existing group hierarchy, with defaults reproducing today's look.

**Architecture:** Pure value catalogs (`TerminalTheme`, `TerminalFont`) and a pure appearance resolver extend the existing `EffectiveHostSettings` inheritance rule. `TerminalSession` maps resolved ids → catalog entries and applies them to its SwiftTerm `TerminalView` (font + `installColors`). A session-local font size drives both the resolved size and a pinch gesture; the pinch value is never persisted.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData, SwiftTerm, swift-testing (`import Testing`).

## Global Constraints

- Tests are **pure logic only** — never construct or walk `@Model` (`Host`/`HostGroup`) relationships in unit tests (SwiftData keypath hangs on the iOS 26.5 simulator). Use the generic resolver with plain values.
- Run tests via `scripts/test.sh --build` (recompiles) or `scripts/test.sh` (re-run). Never plain `xcodebuild test`.
- Test framework is **swift-testing**: `import Testing`, `@Test func …()`, `#expect(…)`. Not XCTest.
- Defaults reproduce current look exactly: theme id `"default"` (black bg), font id `"Menlo-Regular"`, size `14`.
- Inherit sentinels: `themeID`/`fontID` `nil` = inherit; `fontSize` `0` = inherit (mirrors existing `port == 0`).
- Zoom clamp range: **8…32** pt. Zoom is **session-only**; never write pinch size back to the model.
- SwiftTerm `installColors(_:)` requires **exactly 16** `Color` values or it no-ops.

---

### Task 1: TerminalTheme catalog

**Files:**
- Create: `pockterm/Features/Terminal/TerminalTheme.swift`
- Test: `pocktermTests/TerminalThemeTests.swift`

**Interfaces:**
- Consumes: SwiftTerm `Color(red8:green8:blue8:)`.
- Produces:
  - `struct TerminalTheme { let id: String; let name: String; let ansi: [Color]; let foreground: Color; let background: Color; let cursor: Color }`
  - `static let all: [TerminalTheme]` (6 presets, first is `default`)
  - `static func theme(id: String) -> TerminalTheme` (fallback to `default`)

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import SwiftTerm
@testable import pockterm

@Test func everyThemeHas16AnsiColors() {
    for theme in TerminalTheme.all {
        #expect(theme.ansi.count == 16, "\(theme.id) must have 16 ANSI colors")
    }
}

@Test func defaultThemeIsFirstAndBlack() {
    #expect(TerminalTheme.all.first?.id == "default")
    let def = TerminalTheme.theme(id: "default")
    #expect(def.background.red == 0 && def.background.green == 0 && def.background.blue == 0)
}

@Test func unknownThemeIdFallsBackToDefault() {
    #expect(TerminalTheme.theme(id: "nope").id == "default")
}

@Test func knownThemeIdLookupSucceeds() {
    #expect(TerminalTheme.theme(id: "dracula").id == "dracula")
    #expect(TerminalTheme.all.map(\.id).sorted()
            == ["default", "dracula", "light", "nord", "solarized-dark", "solarized-light"])
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/test.sh --build`
Expected: FAIL — `TerminalTheme` is undefined (compile error).

- [ ] **Step 3: Write minimal implementation**

```swift
import SwiftTerm

/// A curated terminal color scheme. Pure value type — no UIKit/SwiftData
/// coupling — so it is fully unit-testable. `ansi` is the 16 ANSI colors in
/// SwiftTerm's expected order (0-7 normal, 8-15 bright).
struct TerminalTheme: Identifiable {
    let id: String
    let name: String
    let ansi: [Color]
    let foreground: Color
    let background: Color
    let cursor: Color

    private static func c(_ hex: UInt32) -> Color {
        Color(red8: UInt8((hex >> 16) & 0xff),
              green8: UInt8((hex >> 8) & 0xff),
              blue8: UInt8(hex & 0xff))
    }

    private static func theme(_ id: String, _ name: String,
                              ansi: [UInt32], fg: UInt32, bg: UInt32, cursor: UInt32) -> TerminalTheme {
        TerminalTheme(id: id, name: name, ansi: ansi.map(c),
                      foreground: c(fg), background: c(bg), cursor: c(cursor))
    }

    static let all: [TerminalTheme] = [
        theme("default", "Default", ansi: [
            0x000000, 0xcd0000, 0x00cd00, 0xcdcd00, 0x0000ee, 0xcd00cd, 0x00cdcd, 0xe5e5e5,
            0x7f7f7f, 0xff0000, 0x00ff00, 0xffff00, 0x5c5cff, 0xff00ff, 0x00ffff, 0xffffff],
            fg: 0xe5e5e5, bg: 0x000000, cursor: 0xe5e5e5),
        theme("solarized-dark", "Solarized Dark", ansi: [
            0x073642, 0xdc322f, 0x859900, 0xb58900, 0x268bd2, 0xd33682, 0x2aa198, 0xeee8d5,
            0x002b36, 0xcb4b16, 0x586e75, 0x657b83, 0x839496, 0x6c71c4, 0x93a1a1, 0xfdf6e3],
            fg: 0x839496, bg: 0x002b36, cursor: 0x839496),
        theme("solarized-light", "Solarized Light", ansi: [
            0xeee8d5, 0xdc322f, 0x859900, 0xb58900, 0x268bd2, 0xd33682, 0x2aa198, 0x073642,
            0xfdf6e3, 0xcb4b16, 0x93a1a1, 0x839496, 0x657b83, 0x6c71c4, 0x586e75, 0x002b36],
            fg: 0x657b83, bg: 0xfdf6e3, cursor: 0x657b83),
        theme("nord", "Nord", ansi: [
            0x3b4252, 0xbf616a, 0xa3be8c, 0xebcb8b, 0x81a1c1, 0xb48ead, 0x88c0d0, 0xe5e9f0,
            0x4c566a, 0xbf616a, 0xa3be8c, 0xebcb8b, 0x81a1c1, 0xb48ead, 0x8fbcbb, 0xeceff4],
            fg: 0xd8dee9, bg: 0x2e3440, cursor: 0xd8dee9),
        theme("dracula", "Dracula", ansi: [
            0x21222c, 0xff5555, 0x50fa7b, 0xf1fa8c, 0xbd93f9, 0xff79c6, 0x8be9fd, 0xf8f8f2,
            0x6272a4, 0xff6e6e, 0x69ff94, 0xffffa5, 0xd6acff, 0xff92df, 0xa4ffff, 0xffffff],
            fg: 0xf8f8f2, bg: 0x282a36, cursor: 0xf8f8f2),
        theme("light", "Light", ansi: [
            0x000000, 0xc91b00, 0x00c200, 0xc7c400, 0x0225c7, 0xc930c7, 0x00c5c7, 0xc7c7c7,
            0x686868, 0xff6e67, 0x5ffa68, 0xfffc67, 0x6871ff, 0xff77ff, 0x60fdff, 0xffffff],
            fg: 0x000000, bg: 0xffffff, cursor: 0x000000),
    ]

    static func theme(id: String) -> TerminalTheme {
        all.first { $0.id == id } ?? all[0]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test.sh --build`
Expected: PASS — all four `TerminalTheme` tests green.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Features/Terminal/TerminalTheme.swift pocktermTests/TerminalThemeTests.swift
git commit -m "Add curated TerminalTheme catalog"
```

---

### Task 2: TerminalFont catalog

**Files:**
- Create: `pockterm/Features/Terminal/TerminalFont.swift`
- Test: `pocktermTests/TerminalFontTests.swift`

**Interfaces:**
- Consumes: `UIFont(name:size:)`.
- Produces:
  - `struct TerminalFont { let id: String; let name: String }`
  - `static let all: [TerminalFont]`
  - `static func available() -> [TerminalFont]` (filters `all` to fonts that instantiate)
  - `static func font(id: String) -> TerminalFont` (fallback to Menlo, id `"Menlo-Regular"`)

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import UIKit
@testable import pockterm

@Test func menloIsTheDefaultFont() {
    #expect(TerminalFont.all.first?.id == "Menlo-Regular")
    #expect(TerminalFont.font(id: "Menlo-Regular").name == "Menlo")
}

@Test func unknownFontIdFallsBackToMenlo() {
    #expect(TerminalFont.font(id: "Comic Sans").id == "Menlo-Regular")
}

@Test func availableFontsAreAllInstantiableAndNonEmpty() {
    let avail = TerminalFont.available()
    #expect(!avail.isEmpty)
    for f in avail {
        #expect(UIFont(name: f.id, size: 12) != nil, "\(f.id) should instantiate")
    }
    // Menlo ships on every iOS, so it must survive the filter.
    #expect(avail.contains { $0.id == "Menlo-Regular" })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/test.sh --build`
Expected: FAIL — `TerminalFont` is undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import UIKit

/// A curated monospaced font the terminal can use. `id` is the exact
/// `UIFont(name:)` PostScript/family name; `name` is the display label.
/// Nothing is bundled — the list is filtered at runtime to fonts iOS actually
/// provides via `available()`.
struct TerminalFont: Identifiable {
    let id: String
    let name: String

    static let all: [TerminalFont] = [
        TerminalFont(id: "Menlo-Regular", name: "Menlo"),
        TerminalFont(id: "SFMono-Regular", name: "SF Mono"),
        TerminalFont(id: "CourierNewPSMT", name: "Courier New"),
        TerminalFont(id: "Courier", name: "Courier"),
    ]

    static func available() -> [TerminalFont] {
        all.filter { UIFont(name: $0.id, size: 12) != nil }
    }

    static func font(id: String) -> TerminalFont {
        all.first { $0.id == id } ?? all[0]
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test.sh --build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Features/Terminal/TerminalFont.swift pocktermTests/TerminalFontTests.swift
git commit -m "Add curated TerminalFont catalog"
```

---

### Task 3: Zoom clamp function

**Files:**
- Create: `pockterm/Features/Terminal/TerminalZoom.swift`
- Test: `pocktermTests/TerminalZoomTests.swift`

**Interfaces:**
- Produces: `enum TerminalZoom { static let minSize = 8; static let maxSize = 32; static func clamped(base: Int, scale: CGFloat) -> Int }`

- [ ] **Step 1: Write the failing test**

```swift
import Testing
import CoreGraphics
@testable import pockterm

@Test func zoomClampsToLowerBound() {
    #expect(TerminalZoom.clamped(base: 10, scale: 0.1) == 8)
}

@Test func zoomClampsToUpperBound() {
    #expect(TerminalZoom.clamped(base: 20, scale: 10) == 32)
}

@Test func zoomRoundsMidRange() {
    // 14 * 1.2 = 16.8 -> 17
    #expect(TerminalZoom.clamped(base: 14, scale: 1.2) == 17)
    // 14 * 1.0 stays 14
    #expect(TerminalZoom.clamped(base: 14, scale: 1.0) == 14)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/test.sh --build`
Expected: FAIL — `TerminalZoom` undefined.

- [ ] **Step 3: Write minimal implementation**

```swift
import CoreGraphics

/// Pure zoom math for the terminal's pinch gesture, factored out for testing.
enum TerminalZoom {
    static let minSize = 8
    static let maxSize = 32

    /// Multiplies `base` by the gesture `scale`, rounds to the nearest point,
    /// and clamps to the legible `minSize…maxSize` band.
    static func clamped(base: Int, scale: CGFloat) -> Int {
        let scaled = Int((CGFloat(base) * scale).rounded())
        return min(maxSize, max(minSize, scaled))
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test.sh --build`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Features/Terminal/TerminalZoom.swift pocktermTests/TerminalZoomTests.swift
git commit -m "Add TerminalZoom clamp math"
```

---

### Task 4: Appearance resolver in EffectiveHostSettings

**Files:**
- Modify: `pockterm/Vault/EffectiveHostSettings.swift`
- Test: `pocktermTests/EffectiveAppearanceTests.swift`

**Interfaces:**
- Consumes: nothing new.
- Produces (pure, generic-free — plain optionals so tests stay SwiftData-free):
  ```swift
  static func resolveAppearance(
      hostTheme: String?, hostFont: String?, hostSize: Int,
      chain: [(theme: String?, font: String?, size: Int?)]
  ) -> (theme: String, font: String, size: Int)
  ```

- [ ] **Step 1: Write the failing test**

```swift
import Testing
@testable import pockterm

@Test func appearanceHostValuesWin() {
    let r = EffectiveHostSettings.resolveAppearance(
        hostTheme: "nord", hostFont: "Courier", hostSize: 18,
        chain: [(theme: "dracula", font: "Menlo-Regular", size: 20)])
    #expect(r.theme == "nord")
    #expect(r.font == "Courier")
    #expect(r.size == 18)
}

@Test func appearanceInheritsFromNearestGroup() {
    let r = EffectiveHostSettings.resolveAppearance(
        hostTheme: nil, hostFont: nil, hostSize: 0,
        chain: [(theme: nil, font: nil, size: nil),
                (theme: "dracula", font: "SFMono-Regular", size: 22)])
    #expect(r.theme == "dracula")
    #expect(r.font == "SFMono-Regular")
    #expect(r.size == 22)
}

@Test func appearanceFallsBackToDefaults() {
    let r = EffectiveHostSettings.resolveAppearance(
        hostTheme: nil, hostFont: nil, hostSize: 0, chain: [])
    #expect(r.theme == "default")
    #expect(r.font == "Menlo-Regular")
    #expect(r.size == 14)
}

@Test func appearanceSizeSentinelZeroInherits() {
    let r = EffectiveHostSettings.resolveAppearance(
        hostTheme: nil, hostFont: nil, hostSize: 0,
        chain: [(theme: nil, font: nil, size: 16)])
    #expect(r.size == 16)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `scripts/test.sh --build`
Expected: FAIL — `resolveAppearance` undefined.

- [ ] **Step 3: Write minimal implementation**

Add to `EffectiveHostSettings` (alongside the existing `resolve` methods), and add stored appearance fields to the struct:

```swift
    // Appended to the struct's stored properties:
    let themeID: String
    let fontID: String
    let fontSize: Int
```

```swift
    /// Pure appearance inheritance, mirroring `resolve(hostPort:…)`: a non-nil
    /// host value wins; else the nearest ancestor group that defines it; else a
    /// built-in default. `chain` is the host's ancestor groups, nearest first.
    static func resolveAppearance(
        hostTheme: String?, hostFont: String?, hostSize: Int,
        chain: [(theme: String?, font: String?, size: Int?)]
    ) -> (theme: String, font: String, size: Int) {
        let theme = hostTheme ?? chain.compactMap { $0.theme }.first ?? "default"
        let font = hostFont ?? chain.compactMap { $0.font }.first ?? "Menlo-Regular"
        let size = hostSize != 0 ? hostSize : (chain.compactMap { $0.size }.first ?? 14)
        return (theme, font, size)
    }
```

Note: because the struct gains three new stored properties, update the existing `resolve(host:)` return at the end of the file to also supply them (see Task 5, which adds the model fields it reads). For this task, to keep the file compiling before the model fields exist, initialize them from the pure resolver with empty inputs:

```swift
        // inside resolve(host:) — temporary until Task 5 wires model fields
        let appear = resolveAppearance(hostTheme: nil, hostFont: nil, hostSize: 0, chain: [])
        return EffectiveHostSettings(port: resolved.port, identity: resolved.identity,
                                     themeID: appear.theme, fontID: appear.font,
                                     fontSize: appear.size)
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `scripts/test.sh --build`
Expected: PASS — appearance tests green; existing inheritance tests still green.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Vault/EffectiveHostSettings.swift pocktermTests/EffectiveAppearanceTests.swift
git commit -m "Add pure appearance resolver to EffectiveHostSettings"
```

---

### Task 5: Model fields on Host and HostGroup + wire resolve(host:)

**Files:**
- Modify: `pockterm/Model/Host.swift`
- Modify: `pockterm/Model/HostGroup.swift`
- Modify: `pockterm/Vault/EffectiveHostSettings.swift` (`resolve(host:)` only)

**Interfaces:**
- Consumes: `resolveAppearance(...)` from Task 4.
- Produces: `Host.themeID/fontID/fontSize`, `HostGroup.defaultThemeID/defaultFontID/defaultFontSize`, and a fully-populated `EffectiveHostSettings.resolve(host:)`.

This task has no pure unit test (it touches `@Model`); it is verified by a clean build. That is deliberate per the Global Constraints.

- [ ] **Step 1: Add Host fields**

In `pockterm/Model/Host.swift`, add stored properties after `lastConnectedAt`:

```swift
    var themeID: String?
    var fontID: String?
    var fontSize: Int
```

Add to the initializer signature (with inherit-defaults) and body:

```swift
    // add params (before the closing paren of init):
         themeID: String? = nil, fontID: String? = nil, fontSize: Int = 0,
    // add assignments in the body:
        self.themeID = themeID
        self.fontID = fontID
        self.fontSize = fontSize
```

- [ ] **Step 2: Add HostGroup fields**

In `pockterm/Model/HostGroup.swift`, add after `defaultPort`:

```swift
    var defaultThemeID: String?
    var defaultFontID: String?
    var defaultFontSize: Int?
```

Add to the initializer:

```swift
    // add params:
         defaultThemeID: String? = nil, defaultFontID: String? = nil,
         defaultFontSize: Int? = nil,
    // add assignments:
        self.defaultThemeID = defaultThemeID
        self.defaultFontID = defaultFontID
        self.defaultFontSize = defaultFontSize
```

- [ ] **Step 3: Wire resolve(host:)**

In `pockterm/Vault/EffectiveHostSettings.swift`, replace the temporary appearance block from Task 4 with the real walk (build the chain once, reuse for both):

```swift
    @MainActor
    static func resolve(host: Host) -> EffectiveHostSettings {
        var portIdentityChain: [(port: Int?, identity: Identity?)] = []
        var appearanceChain: [(theme: String?, font: String?, size: Int?)] = []
        var group = host.group
        while let g = group {
            portIdentityChain.append((g.defaultPort, g.defaultIdentity))
            appearanceChain.append((g.defaultThemeID, g.defaultFontID, g.defaultFontSize))
            group = g.parent
        }
        let resolved = resolve(hostPort: host.port, hostIdentity: host.identity,
                               chain: portIdentityChain)
        let appear = resolveAppearance(hostTheme: host.themeID, hostFont: host.fontID,
                                       hostSize: host.fontSize, chain: appearanceChain)
        return EffectiveHostSettings(port: resolved.port, identity: resolved.identity,
                                     themeID: appear.theme, fontID: appear.font,
                                     fontSize: appear.size)
    }
```

- [ ] **Step 4: Build to verify it compiles**

Run: `scripts/test.sh --build`
Expected: BUILD succeeds; all existing tests still PASS.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Model/Host.swift pockterm/Model/HostGroup.swift pockterm/Vault/EffectiveHostSettings.swift
git commit -m "Add appearance fields to Host/HostGroup and wire resolve(host:)"
```

---

### Task 6: Apply appearance in TerminalSession

**Files:**
- Modify: `pockterm/Features/Terminal/TerminalSession.swift`

**Interfaces:**
- Consumes: `EffectiveHostSettings.resolve(host:)`, `TerminalTheme.theme(id:)`, `TerminalFont.font(id:)`.
- Produces: `TerminalSession.currentFontSize: Int`, `func applyAppearance()`.

Verified by build + the simulator `verify` harness (connect a host, confirm the terminal renders with the resolved theme/font). No unit test — it drives UIKit/SwiftTerm.

- [ ] **Step 1: Add stored size + apply method**

In `TerminalSession`, add a stored property near `terminalView`:

```swift
    /// Session-local font size: seeded from resolved settings, mutated live by
    /// pinch-zoom, and never written back to the model (zoom is session-only).
    var currentFontSize: Int = 14
```

Add the apply method:

```swift
    /// Resolves this host's effective appearance and applies it to the
    /// terminal view (font + full ANSI palette + native fg/bg/cursor).
    func applyAppearance() {
        let s = EffectiveHostSettings.resolve(host: host)
        let theme = TerminalTheme.theme(id: s.themeID)
        let fontID = TerminalFont.font(id: s.fontID).id
        let size = CGFloat(currentFontSize)
        terminalView.font = UIFont(name: fontID, size: size)
            ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        if theme.ansi.count == 16 { terminalView.installColors(theme.ansi) }
        terminalView.nativeForegroundColor = TerminalTheme.uiColor(theme.foreground)
        terminalView.nativeBackgroundColor = TerminalTheme.uiColor(theme.background)
        terminalView.backgroundColor = TerminalTheme.uiColor(theme.background)
        terminalView.caretColor = TerminalTheme.uiColor(theme.cursor)
    }
```

- [ ] **Step 2: Add the Color→UIColor helper**

SwiftTerm `Color` components are `UInt16` 0…65535. Add to `TerminalTheme.swift`:

```swift
import UIKit

extension TerminalTheme {
    /// Converts a SwiftTerm 16-bit `Color` to a `UIColor`.
    static func uiColor(_ c: Color) -> UIColor {
        UIColor(red: CGFloat(c.red) / 65535, green: CGFloat(c.green) / 65535,
                blue: CGFloat(c.blue) / 65535, alpha: 1)
    }
}
```

- [ ] **Step 3: Seed size and call applyAppearance in init**

In `TerminalSession.init`, replace the line `terminalView.backgroundColor = .black` with:

```swift
        self.currentFontSize = EffectiveHostSettings.resolve(host: host).fontSize
        applyAppearance()
```

(Place `applyAppearance()` after `terminalView.terminalDelegate = proxy` so the view exists; `currentFontSize` assignment must precede `applyAppearance()`.)

- [ ] **Step 4: Build and smoke-test**

Run: `scripts/test.sh --build`
Expected: BUILD succeeds, tests PASS.
Then run the `verify` skill: connect to a host and confirm the terminal shows the Default (black) theme unchanged. Change the host's theme in the DB/editor (after Task 8) is not required here — Default must look identical to today.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Features/Terminal/TerminalSession.swift pockterm/Features/Terminal/TerminalTheme.swift
git commit -m "Apply resolved theme/font to the terminal view"
```

---

### Task 7: Pinch-to-zoom gesture

**Files:**
- Modify: `pockterm/Features/Terminal/TerminalSession.swift`

**Interfaces:**
- Consumes: `TerminalZoom.clamped(base:scale:)`, `currentFontSize`, `applyAppearance()`.
- Produces: pinch handling on `terminalView`.

Verified via simulator `verify` (pinch on the terminal, watch text grow/shrink and reflow, bounded 8–32).

- [ ] **Step 1: Add a pinch recognizer and handler**

Add a stored property to hold the gesture's starting size:

```swift
    private var zoomStartSize: Int = 14
```

In `init`, after `applyAppearance()`, install the recognizer:

```swift
        let pinch = UIPinchGestureRecognizer(target: proxy, action: nil)
        proxy.onPinch = { [weak self] recognizer in self?.handlePinch(recognizer) }
        pinch.delegate = proxy   // allow simultaneous recognition with SwiftTerm
        terminalView.addGestureRecognizer(pinch)
```

Add the handler:

```swift
    private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            zoomStartSize = currentFontSize
        case .changed:
            let size = TerminalZoom.clamped(base: zoomStartSize, scale: recognizer.scale)
            if size != currentFontSize {
                currentFontSize = size
                applyAppearance()
            }
        default:
            break
        }
    }
```

- [ ] **Step 2: Extend the delegate proxy**

`TerminalSession` uses a `TerminalDelegateProxy`. Add pinch plumbing to it (same file where it is defined — search for `class TerminalDelegateProxy`). Add:

```swift
    var onPinch: ((UIPinchGestureRecognizer) -> Void)?

    @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        onPinch?(recognizer)
    }
```

And conform the proxy to `UIGestureRecognizerDelegate` so simultaneous recognition is allowed:

```swift
extension TerminalDelegateProxy: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
```

Fix the recognizer target/action to call the proxy method:

```swift
        let pinch = UIPinchGestureRecognizer(target: proxy, action: #selector(TerminalDelegateProxy.handlePinch(_:)))
```

(Remove the `pinch.delegate = proxy` duplication if already set; keep exactly one assignment. Keep the `proxy.onPinch = …` closure assignment.)

- [ ] **Step 3: Build**

Run: `scripts/test.sh --build`
Expected: BUILD succeeds, tests PASS.

- [ ] **Step 4: Simulator verify**

Run the `verify` skill; pinch out/in on the terminal. Expected: font grows/shrinks and text reflows; stops at 8pt (min) and 32pt (max); releasing keeps the size for the session; reopening the host reverts to the saved size.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Features/Terminal/TerminalSession.swift
git commit -m "Add session-only pinch-to-zoom to the terminal"
```

---

### Task 8: Host editor Appearance section

**Files:**
- Modify: `pockterm/Features/Hosts/HostEditorView.swift`

**Interfaces:**
- Consumes: `TerminalTheme.all`, `TerminalFont.available()`, bindings on `Host`.
- Produces: an Appearance section binding `host.themeID`, `host.fontID`, `host.fontSize`.

UI task, verified by simulator `verify`.

- [ ] **Step 1: Add the Appearance section**

Insert after the `Organization` section in the `Form`:

```swift
                Section("Appearance") {
                    Picker("Theme", selection: $host.themeID) {
                        Text("Default (inherit)").tag(String?.none)
                        ForEach(TerminalTheme.all) { theme in
                            Text(theme.name).tag(String?.some(theme.id))
                        }
                    }
                    Picker("Font", selection: $host.fontID) {
                        Text("Default (inherit)").tag(String?.none)
                        ForEach(TerminalFont.available()) { font in
                            Text(font.name).tag(String?.some(font.id))
                        }
                    }
                    Stepper(host.fontSize == 0 ? "Size: Default"
                                               : "Size: \(host.fontSize)pt",
                            value: $host.fontSize,
                            in: 0...TerminalZoom.maxSize)
                }
```

Note: the stepper's lower bound `0` is the inherit sentinel shown as "Default"; the next value is `1`, but the effective floor when a real size is chosen should be `TerminalZoom.minSize`. To avoid a `1…7` dead zone, clamp in the label/save path:

- [ ] **Step 2: Normalize sub-minimum sizes on save**

In `save()`, before `try? ctx.save()`, add:

```swift
        if host.fontSize != 0 && host.fontSize < TerminalZoom.minSize {
            host.fontSize = TerminalZoom.minSize
        }
```

- [ ] **Step 3: Build**

Run: `scripts/test.sh --build`
Expected: BUILD succeeds, tests PASS.

- [ ] **Step 4: Simulator verify**

Run `verify`: open a host editor, pick Dracula + SF Mono + size 18, save, connect. Expected: the terminal renders Dracula/SF Mono at 18pt. Set them back to Default and confirm the black/Menlo/14 look returns.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Features/Hosts/HostEditorView.swift
git commit -m "Add Appearance section to host editor"
```

---

### Task 9: Group editor Appearance defaults

**Files:**
- Modify: `pockterm/Features/Groups/GroupEditorView.swift`

**Interfaces:**
- Consumes: `TerminalTheme.all`, `TerminalFont.available()`, bindings on `HostGroup`.
- Produces: an Appearance section binding `group.defaultThemeID`, `group.defaultFontID`, `group.defaultFontSize`.

- [ ] **Step 1: Read the current group editor**

Run: `sed -n '1,80p' pockterm/Features/Groups/GroupEditorView.swift`
Expected: a `Form`-based editor with a `@Bindable var group: HostGroup`. Note the existing section names and the save path to match style.

- [ ] **Step 2: Add the Appearance defaults section**

Insert a new `Section` in the group `Form` (matching the file's existing structure):

```swift
                Section("Appearance Defaults") {
                    Picker("Theme", selection: $group.defaultThemeID) {
                        Text("None").tag(String?.none)
                        ForEach(TerminalTheme.all) { theme in
                            Text(theme.name).tag(String?.some(theme.id))
                        }
                    }
                    Picker("Font", selection: $group.defaultFontID) {
                        Text("None").tag(String?.none)
                        ForEach(TerminalFont.available()) { font in
                            Text(font.name).tag(String?.some(font.id))
                        }
                    }
                    Picker("Size", selection: $group.defaultFontSize) {
                        Text("None").tag(Int?.none)
                        ForEach(Array(stride(from: TerminalZoom.minSize,
                                             through: TerminalZoom.maxSize, by: 2)), id: \.self) { s in
                            Text("\(s)pt").tag(Int?.some(s))
                        }
                    }
                }
```

- [ ] **Step 3: Build**

Run: `scripts/test.sh --build`
Expected: BUILD succeeds, tests PASS.

- [ ] **Step 4: Simulator verify**

Run `verify`: set a group's default theme to Nord; assign a host (with Default appearance) to that group; connect. Expected: the host inherits Nord. Override the host's theme to Dracula and confirm the host value wins.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Features/Groups/GroupEditorView.swift
git commit -m "Add appearance defaults to group editor"
```

---

### Task 10: Live preview line in editors

**Files:**
- Create: `pockterm/Features/Terminal/ThemePreviewRow.swift`
- Modify: `pockterm/Features/Hosts/HostEditorView.swift`
- Modify: `pockterm/Features/Groups/GroupEditorView.swift`

**Interfaces:**
- Consumes: `TerminalTheme.theme(id:)`, `TerminalFont.font(id:)`, `TerminalTheme.uiColor(_:)`.
- Produces: `struct ThemePreviewRow: View` — a SwiftUI row showing `user@host:~$ ls` rendered in a given theme + font.

UI task, verified by simulator `verify`.

- [ ] **Step 1: Create the preview view**

```swift
import SwiftUI

/// A one-line preview of a theme + font: a sample shell prompt drawn with the
/// theme's background/foreground and the chosen monospaced font.
struct ThemePreviewRow: View {
    let themeID: String
    let fontID: String

    var body: some View {
        let theme = TerminalTheme.theme(id: themeID)
        let fontName = TerminalFont.font(id: fontID).id
        Text("user@host:~$ ls")
            .font(Font(UIFont(name: fontName, size: 14)
                       ?? UIFont.monospacedSystemFont(ofSize: 14, weight: .regular)))
            .foregroundStyle(Color(TerminalTheme.uiColor(theme.foreground)))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color(TerminalTheme.uiColor(theme.background)))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
```

- [ ] **Step 2: Add the preview to the host editor Appearance section**

At the end of the `Section("Appearance")` block in `HostEditorView.swift`, resolve the effective ids for preview (host value or a sensible fallback so the row is never blank):

```swift
                    ThemePreviewRow(themeID: host.themeID ?? "default",
                                    fontID: host.fontID ?? "Menlo-Regular")
```

- [ ] **Step 3: Add the preview to the group editor**

At the end of `Section("Appearance Defaults")` in `GroupEditorView.swift`:

```swift
                    ThemePreviewRow(themeID: group.defaultThemeID ?? "default",
                                    fontID: group.defaultFontID ?? "Menlo-Regular")
```

- [ ] **Step 4: Build**

Run: `scripts/test.sh --build`
Expected: BUILD succeeds, tests PASS.

- [ ] **Step 5: Simulator verify**

Run `verify`: open the host editor, change theme/font and confirm the preview row updates to show the sample prompt in the selected colors/font.

- [ ] **Step 6: Commit**

```bash
git add pockterm/Features/Terminal/ThemePreviewRow.swift pockterm/Features/Hosts/HostEditorView.swift pockterm/Features/Groups/GroupEditorView.swift
git commit -m "Add live theme/font preview row to editors"
```

---

## Self-Review

**Spec coverage:**
- Data model & inheritance → Tasks 4, 5. ✅
- Theme catalog (6 presets) → Task 1. ✅
- Font catalog (curated system, `available()` filter) → Task 2. ✅
- Apply to live terminal (`installColors`, font, fg/bg/cursor) → Task 6. ✅
- Pinch-zoom, session-only, 8–32, reflow → Tasks 3, 7. ✅
- Host editor UI (inherit option) → Task 8. ✅
- Group editor UI → Task 9. ✅
- Preview line in pickers → Task 10. ✅
- Testing (pure resolver, catalog, zoom) → Tasks 1–4. ✅

**Placeholder scan:** No TBD/TODO; all code blocks are concrete, including full color palettes.

**Type consistency:** `TerminalTheme.theme(id:)`, `TerminalFont.font(id:)`/`available()`, `TerminalZoom.clamped(base:scale:)`/`minSize`/`maxSize`, `resolveAppearance(hostTheme:hostFont:hostSize:chain:)`, `applyAppearance()`, `currentFontSize`, `TerminalTheme.uiColor(_:)`, `ThemePreviewRow(themeID:fontID:)` are used consistently across tasks. `EffectiveHostSettings` gains `themeID`/`fontID`/`fontSize` (Task 4), populated in `resolve(host:)` (Task 5).
