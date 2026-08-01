# Reset Terminal Zoom to Default Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a one-tap control that undoes terminal pinch-zoom, returning the terminal to the host's resolved/saved font size, with a haptic + transient "Default size" HUD confirming the un-zoomed state.

**Architecture:** Extend the existing session-only zoom on `TerminalSession` with a captured baseline size, an `isZoomed` flag, and a `resetZoom()` method (reusing the same `applyAppearance()` reflow path pinch uses). Add a small SwiftUI overlay (`ZoomControlsView`) into the terminal's existing `ZStack` in `SessionTabsView`: a reset pill shown only while zoomed, and a transient confirmation HUD.

**Tech Stack:** Swift 6.2, SwiftUI, Observation (`@Observable`), SwiftTerm, UIKit (`UIImpactFeedbackGenerator`).

## Global Constraints

- **Session-only:** reset, like zoom, must NEVER write back to `Host.fontSize`, `HostGroup`, or any `@Model`. It only mutates the in-memory `TerminalSession.currentFontSize`. (Mirrors the existing pinch-zoom contract.)
- **Baseline = resolved size at session start:** `EffectiveHostSettings.resolve(host:).fontSize`, captured once in `init`.
- **Zoom clamp unchanged:** the existing 8–32pt band and `TerminalZoom.clamped` logic are not modified.
- **No pbxproj edit for the new view:** files added under `pockterm/` are auto-included by the `PBXFileSystemSynchronizedRootGroup` (only test files need pbxproj entries).
- **Unit-test constraint:** constructing a `TerminalSession` in a unit test resolves `@Model` relationships in `init`, which hangs the iOS 26.5 simulator (see `pockterm-swiftdata-test-hangs`). Do NOT add unit tests that instantiate `TerminalSession`. Terminal/overlay wiring is verified via the simulator `verify` harness; the existing `TerminalZoom.clamped` unit tests must stay green.
- **Build/test command:** `scripts/test.sh --build` (never plain `xcodebuild test`).

---

### Task 1: Baseline, `isZoomed`, and `resetZoom()` on `TerminalSession`

**Files:**
- Modify: `pockterm/Features/Terminal/TerminalSession.swift`

**Interfaces:**
- Consumes: existing `currentFontSize: Int`, `applyAppearance()`, and `EffectiveHostSettings.resolve(host:)` (already used in `init`).
- Produces (used by Task 2):
  - `let baselineFontSize: Int`
  - `var isZoomed: Bool { get }` — `currentFontSize != baselineFontSize`
  - `func resetZoom()` — snaps `currentFontSize` to `baselineFontSize` and re-applies appearance; no-op when already at baseline.

**Context:** `TerminalSession` (`@MainActor @Observable final class`) already declares `var currentFontSize: Int = 14` and, in `init`, sets `self.currentFontSize = EffectiveHostSettings.resolve(host: host).fontSize` immediately followed by `applyAppearance()`. `applyAppearance()` reads `currentFontSize` and applies the font to `terminalView`. Pinch-zoom mutates `currentFontSize` and calls `applyAppearance()`.

- [ ] **Step 1: Add the `baselineFontSize` stored property**

Add this declaration next to `currentFontSize` (which is currently `var currentFontSize: Int = 14`):

```swift
/// The un-zoomed size for this session: the resolved size captured at
/// session start. Reset returns `currentFontSize` to this value. Like
/// `currentFontSize`, it is session-only and never persisted.
let baselineFontSize: Int
```

- [ ] **Step 2: Assign `baselineFontSize` in `init` before `applyAppearance()`**

In `init`, the two existing lines are:

```swift
        self.currentFontSize = EffectiveHostSettings.resolve(host: host).fontSize
        applyAppearance()
```

Replace them with (assign the baseline BEFORE the first method call on `self`, so all stored properties are initialized before `applyAppearance()` runs):

```swift
        let resolvedSize = EffectiveHostSettings.resolve(host: host).fontSize
        self.currentFontSize = resolvedSize
        self.baselineFontSize = resolvedSize
        applyAppearance()
```

- [ ] **Step 3: Add `isZoomed` and `resetZoom()`**

Add these members to `TerminalSession` (place them next to `handlePinch(_:)`, the other zoom code):

```swift
    /// True when the live session size differs from the un-zoomed baseline.
    /// Drives the reset control's visibility.
    var isZoomed: Bool { currentFontSize != baselineFontSize }

    /// Session-only: return the terminal to its baseline size and reflow.
    /// No-op when already at baseline. Never writes back to `Host`.
    func resetZoom() {
        guard currentFontSize != baselineFontSize else { return }
        currentFontSize = baselineFontSize
        applyAppearance()
    }
```

- [ ] **Step 4: Build and run the existing suite to confirm nothing regressed**

Run: `scripts/test.sh --build`
Expected: BUILD SUCCEEDS and all existing tests pass (including `TerminalZoom` tests). No new tests are added in this task — see the Global Constraints unit-test note; `TerminalSession` cannot be instantiated in a unit test.

- [ ] **Step 5: Commit**

```bash
git add pockterm/Features/Terminal/TerminalSession.swift
git commit -m "Add session-only zoom baseline, isZoomed, and resetZoom()"
```

---

### Task 2: `ZoomControlsView` (reset pill + HUD) wired into `SessionTabsView`

**Files:**
- Create: `pockterm/Features/Terminal/ZoomControlsView.swift`
- Modify: `pockterm/Features/Terminal/SessionTabsView.swift` (inside `sessionContent(_:)`)

**Interfaces:**
- Consumes (from Task 1): `session.isZoomed`, `session.currentFontSize`, `session.resetZoom()`.
- Produces: `struct ZoomControlsView: View` taking a `TerminalSession`.

**Context:** `SessionTabsView.sessionContent(_:)` returns a `ZStack` whose first child is `TerminalHostView(terminalView: session.terminalView)`, followed by a `switch session.status` rendering status overlays (`.connected` renders `EmptyView()`). `TerminalSession` is `@Observable`, so reading its properties in a SwiftUI body tracks them. `Status` is `Equatable`.

- [ ] **Step 1: Create `ZoomControlsView`**

Create `pockterm/Features/Terminal/ZoomControlsView.swift`:

```swift
import SwiftUI
import UIKit

/// Session-only zoom controls overlaid on the terminal: a reset pill shown
/// only while the session is zoomed away from its baseline, and a transient
/// "Default size" HUD (plus a light haptic) confirming a reset.
struct ZoomControlsView: View {
    let session: TerminalSession

    @State private var showHUD = false
    @State private var hudDismissTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Reset pill — top-trailing, only while zoomed.
            if session.isZoomed {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: reset) {
                            Label("\(session.currentFontSize)pt",
                                  systemImage: "arrow.counterclockwise")
                                .font(.footnote.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(.regularMaterial, in: Capsule())
                        }
                        .tint(.primary)
                        .accessibilityLabel("Reset zoom to default size")
                    }
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.trailing, 12)
                .transition(.opacity.combined(with: .scale))
            }

            // Transient confirmation HUD — centered, non-interactive.
            if showHUD {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 34, weight: .semibold))
                    Text("Default size")
                        .font(.callout.weight(.medium))
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                .transition(.opacity)
                .allowsHitTesting(false)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: session.isZoomed)
        .animation(.easeInOut(duration: 0.2), value: showHUD)
    }

    private func reset() {
        session.resetZoom()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Show the HUD, cancelling any in-flight dismiss so rapid taps don't
        // stack or clip the confirmation.
        hudDismissTask?.cancel()
        showHUD = true
        hudDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.9))
            if !Task.isCancelled { showHUD = false }
        }
    }
}
```

- [ ] **Step 2: Wire it into `SessionTabsView.sessionContent(_:)`**

In `sessionContent(_:)`, the `ZStack` currently ends after the `switch session.status { … }`. Add the overlay as the last child of that `ZStack`, gated on the connected state (zoom only applies to a live terminal):

```swift
            if session.status == .connected {
                ZoomControlsView(session: session)
            }
```

Place it immediately after the closing brace of the `switch`, still inside the `ZStack`.

- [ ] **Step 3: Build and run the suite**

Run: `scripts/test.sh --build`
Expected: BUILD SUCCEEDS; all existing tests pass. No new unit tests (UIKit/SwiftUI overlay + haptic; see Global Constraints).

- [ ] **Step 4: Commit**

```bash
git add pockterm/Features/Terminal/ZoomControlsView.swift pockterm/Features/Terminal/SessionTabsView.swift
git commit -m "Add reset-zoom pill and Default-size HUD over the terminal"
```

---

## Verification (after both tasks)

Simulator `verify` harness (the `.claude/skills/verify` flow), since the overlay, haptic, and reflow cannot be unit-tested:

1. Connect a session (`john@localhost:22`).
2. Pinch to zoom the terminal away from baseline → confirm the reset pill appears top-trailing showing the current pt size.
3. Tap the pill → confirm the terminal reflows back to the baseline size, the "Default size" HUD appears and fades after ~1s, and the pill disappears (session no longer zoomed).
4. Confirm the pill is absent at baseline (no zoom applied).
