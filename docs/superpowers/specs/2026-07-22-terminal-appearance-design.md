# Terminal Appearance: Theme, Font, and Pinch-to-Zoom

**Date:** 2026-07-22
**Status:** Approved design, ready for planning

## Summary

Give pockterm's terminal configurable appearance: a **theme selector**, a
**font selector**, and **pinch-to-zoom** on the terminal. All three are
**per-host** settings that inherit through the existing group hierarchy, and
all defaults reproduce today's look (all-black background, Menlo, 14pt) so
existing users see no change until they opt in.

Out of scope: the "China / App Review" storefront work (deferred). No bundled
font files, no follow-the-system theme.

## Decisions

| Area | Decision |
|---|---|
| Zoom behavior | Font-size zoom with **reflow** (not pixel magnification) |
| Zoom persistence | **Session-only** — pinch does not write back to the saved size |
| Zoom bounds | Clamp **8pt – 32pt** |
| Settings scope | **Per-host override** with group inheritance |
| Themes | **Curated presets only** (no follow-system): Default (Black), Solarized Dark, Solarized Light, Nord, Dracula, Light |
| Fonts | **Curated system monospaced list** (Menlo default, SF Mono, Courier New, …); nothing bundled |
| Defaults | theme `default` (current black), font `Menlo`, size `14` |

## 1. Data model & inheritance

Appearance resolves through the **existing** `EffectiveHostSettings` rule:
host value wins → nearest ancestor group that defines it → built-in default.
The resolver stays generic (`resolve<ID>(...)`) so tests exercise pure values
and never walk `@Model` relationships (SwiftData keypath hangs on the iOS 26.5
simulator — see `pockterm-swiftdata-test-hangs`).

New fields:

- `Host`: `themeID: String?`, `fontID: String?`, `fontSize: Int`
  - `themeID`/`fontID`: `nil` means inherit.
  - `fontSize`: `0` is the inherit sentinel (mirrors the existing `port == 0`
    "Default" convention).
- `HostGroup`: `defaultThemeID: String?`, `defaultFontID: String?`,
  `defaultFontSize: Int?`

Built-in defaults: theme `"default"`, font `"Menlo"`, size `14`.

`EffectiveHostSettings` gains resolved `themeID: String`, `fontID: String`,
`fontSize: Int`, produced by the same generic resolver already in the file.
(It resolves to **ids**, not catalog objects, to keep it free of UIKit/SwiftTerm
coupling; callers map ids → catalog entries.)

### SwiftData migration

Adding optional properties (and an `Int` with a default) to existing `@Model`
types is a lightweight, additive schema change. Existing stored hosts/groups
decode with `nil`/`0`, i.e. "inherit → default", preserving current appearance.

## 2. Theme & font catalogs (pure value types)

`TerminalTheme` — plain struct, no SwiftData/UIKit coupling:
- `id: String`, `name: String`
- 16 ANSI colors + `foreground`, `background`, `cursor` (SwiftTerm `Color`).
- `static let all: [TerminalTheme]` holds the six curated presets.
- `static func theme(id:) -> TerminalTheme` — lookup with fallback to
  `default`.

`TerminalFont` — plain struct:
- `id: String` (== PostScript/family name), `name: String` (display).
- `static let all: [TerminalFont]` curated monospaced list.
- `static func available() -> [TerminalFont]` filters `all` to fonts actually
  present via `UIFont(name:size:)`.
- `static func font(id:) -> TerminalFont` — lookup with fallback to `Menlo`.

Both are fully unit-testable: id lookup, unknown-id fallback, ANSI color count
(== 16), unavailable-font fallback.

## 3. Applying appearance to the live terminal

`TerminalSession` currently hardcodes `terminalView.backgroundColor = .black`
in `init`. Replace with `applyAppearance()`:

1. Resolve `EffectiveHostSettings` for `host`.
2. Map resolved ids → `TerminalTheme` / `TerminalFont`.
3. `terminalView.font = UIFont(name: font.id, size: CGFloat(currentFontSize))`
   (fallback `UIFont.monospacedSystemFont` if the named font is missing).
4. `terminalView.installColors(theme.ansiColors)`; set native foreground /
   background / cursor colors and `terminalView.backgroundColor`.

Called on `init` and whenever the host's appearance settings change (e.g. after
the editor saves). `currentFontSize` (see §4) is the size input, so zoom and
settings feed the same apply path.

## 4. Pinch-to-zoom (session-only)

- `TerminalSession` holds a session-local `currentFontSize: Int`, initialized
  to the resolved `fontSize`.
- A `UIPinchGestureRecognizer` on `terminalView` multiplies a scratch size by
  `recognizer.scale` during the gesture, rounds, clamps to **8…32**, and
  applies live by setting `terminalView.font`. SwiftTerm reflows to the new
  column count.
- On gesture end the value persists **for the session only** — it is never
  written back to `Host.fontSize`. Reopening the host resolves the saved /
  inherited size again.
- Clamp/scale is factored as a pure function `clampedZoom(base:scale:) -> Int`
  for unit testing.

### HIG conformance

- Standard pinch semantics: spread = larger, pinch = smaller.
- The recognizer's delegate allows simultaneous recognition so it does not
  suppress SwiftTerm's own selection/scroll gestures.
- Dynamic Type is honored only as the *initial* default size; explicit terminal
  sizing is expected and appropriate for a terminal emulator. Sizes stay within
  a legible 8–32pt band.

## 5. UI surfaces

- **Host editor** gains an **Appearance** section: Theme picker, Font picker,
  Size stepper. Each picker's first option is **"Default (inherit)"**, matching
  the existing port "Default" affordance. Size stepper offers an explicit
  "Default" state (sentinel `0`).
- **Group editor** gains the same three controls, writing the group-level
  `default*` fields.
- Each picker renders a short live preview line (`user@host:~$ ls`) in the
  chosen theme + font so the effect is visible before saving.

## 6. Testing

Pure-logic unit tests, run via `scripts/test.sh` (no `@Model` traversal):

- `EffectiveHostSettings` appearance resolution: host wins; group inheritance
  (nearest ancestor); default fallback; `fontSize == 0` sentinel.
- `TerminalTheme` catalog: id lookup; unknown-id → `default`; ANSI colors count
  == 16 for every preset.
- `TerminalFont` catalog: id lookup; unknown-id → Menlo; `available()` filters
  to present fonts.
- `clampedZoom(base:scale:)`: below-8 clamps to 8; above-32 clamps to 32;
  mid-range rounds correctly.

Terminal wiring that cannot be unit-tested (pinch gesture, `installColors`,
`UIFont` application) is verified through the simulator `verify` harness.

## Non-goals

- Follow-the-system (Automatic) theme.
- Bundled/custom font files.
- Persisting pinch-zoom to the model.
- China storefront / App Review changes.
