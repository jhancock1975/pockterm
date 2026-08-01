# Reset Terminal Zoom to Default

**Date:** 2026-07-28
**Status:** Approved design, ready for planning

## Summary

Give the user a one-tap way to undo terminal pinch-zoom and return to the
host's resolved/saved font size, with clear confirmation that they are back to
the un-zoomed baseline. Builds directly on the existing session-only
pinch-to-zoom (`TerminalSession.currentFontSize`, clamped 8–32pt, never written
back to the model).

Out of scope: persisting or changing the saved size; a keyboard/gesture reset
(reset is a visible button); any change to how pinch-zoom itself works.

## Decisions

| Area | Decision |
|---|---|
| Baseline | The host's resolved font size captured at session start (`EffectiveHostSettings.resolve(host:).fontSize`) |
| "Zoomed" | `currentFontSize != baselineFontSize` |
| Reset action | Snap `currentFontSize` back to `baselineFontSize`, re-apply appearance; no-op if already at baseline |
| Persistence | Reset is session-only, exactly like zoom — never writes back to `Host.fontSize` |
| Trigger | Floating pill button, visible **only while zoomed** |
| Button content | Current size + reset glyph (e.g. `16pt ⟲`) — self-documenting; its presence signals "you're zoomed" |
| Confirmation | Transient center HUD (system material, checkmark + **"Default size"**) fading in/out, plus a light impact haptic on reset |

## 1. Model: `TerminalSession`

`TerminalSession` already owns `currentFontSize` (session-only zoom size) and
`applyAppearance()`. Add:

- `let baselineFontSize: Int` — assigned in `init` immediately after
  `currentFontSize` is resolved, so both start equal. It is the un-zoomed
  reference for this session; like `currentFontSize`, it is not persisted and
  reflects the size resolved at session start.
- `var isZoomed: Bool { currentFontSize != baselineFontSize }` — drives the
  button's visibility.
- `func resetZoom()`:
  - Guard: return early if `currentFontSize == baselineFontSize` (already at
    baseline — nothing to do).
  - Set `currentFontSize = baselineFontSize`.
  - Call `applyAppearance()` (the same path pinch uses), so SwiftTerm reflows to
    the baseline size.

No writes to `Host`/`HostGroup`; reset mirrors zoom's session-only contract.

## 2. UI: floating reset button

Added as an overlay inside the existing `ZStack` in
`SessionTabsView.sessionContent(_:)`, aligned top-trailing, inset from the safe
area so it clears the notch/status area and never overlaps the input accessory
(the terminal's bottom is pinned to the keyboard layout guide, so top-trailing
is clear).

- Rendered **only when `session.isZoomed`**; its appearance/disappearance is
  animated (e.g. `.transition(.opacity.combined(with: .scale))` inside
  `withAnimation`).
- A compact `Capsule`/`.buttonBorderShape(.capsule)` pill showing the current
  size and a reset glyph, e.g. `Label("\(session.currentFontSize)pt",
  systemImage: "arrow.counterclockwise")` styled compactly. Uses a material/
  translucent background so it reads over any terminal theme.
- Tap action: call `session.resetZoom()`, fire the haptic, and trigger the HUD
  (see §3).
- Accessibility: label "Reset zoom to default size".

## 3. UI: confirmation HUD + haptic

A transient, non-interactive overlay centered in the same `ZStack`, shown when a
reset happens (not tied to `isZoomed`, since after reset the session is no
longer zoomed):

- Content: a rounded rectangle with system material background, an SF Symbol
  (e.g. `checkmark` or `textformat.size`) and the text **"Default size"**.
- Lifecycle: fade/scale in, hold ~0.9s, fade out. Implement with a local
  `@State` token/flag in the view and an animation + delayed reset (e.g. a
  `Task` that sleeps then clears the flag, cancelling any in-flight one so rapid
  resets don't stack).
- `.allowsHitTesting(false)` so it never blocks terminal interaction.
- Haptic: `UIImpactFeedbackGenerator(style: .light)` (or `.soft`) triggered in
  the button's tap handler alongside `resetZoom()`.

To keep `SessionTabsView` focused, the button and HUD may live in a small new
view file (e.g. `ZoomControlsView.swift`) that takes the `TerminalSession` and
renders both the conditional button and the transient HUD.

## 4. HIG conformance

- The control appears only when relevant (while zoomed) and disappears once back
  at baseline — no persistent chrome over the terminal.
- The HUD is transient and non-interactive, matching iOS system HUD conventions.
- Pinch-to-zoom (existing) and the reset button are standard, discoverable
  affordances; reset uses the conventional counterclockwise-arrow glyph.
- Reset returns to a legible baseline within the existing 8–32pt band.

## 5. Testing

Pure logic here is a trivial baseline assignment; the meaningful behavior is
UIKit/SwiftUI overlay wiring, `applyAppearance()` reflow, and the haptic — none
unit-testable (`@MainActor`, `TerminalView`, and `@Model` resolution in `init`;
SwiftData keypath walking hangs the iOS 26.5 simulator in unit tests — see
`pockterm-swiftdata-test-hangs`).

- Existing `TerminalZoom.clamped` tests stay green (unchanged).
- Simulator `verify` harness: pinch to zoom away from baseline → confirm the
  reset pill appears → tap it → confirm the terminal returns to the baseline
  size, the "Default size" HUD shows and fades, and the pill disappears. Confirm
  the pill is absent at baseline.

## Non-goals

- Persisting zoom or reset to the model.
- Changing the saved/default font size (that stays in the appearance settings).
- A gesture-based reset (reset is an explicit visible button).
- Any change to pinch-to-zoom behavior or the 8–32pt clamp.
