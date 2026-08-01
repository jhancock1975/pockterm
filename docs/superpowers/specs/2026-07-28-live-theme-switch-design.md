# Live In-Session Theme Switching

**Date:** 2026-07-28
**Status:** Approved design, ready for planning

## Summary

Let the user change a terminal session's **theme** while it is live, from a
control on the terminal screen, and have the change apply instantly. The pick
**persists to the host** (`Host.themeID`), becoming the host's saved default so
it survives reconnects. This reuses the existing appearance plumbing:
`TerminalSession.applyAppearance()` already re-resolves and re-applies the full
theme (`installColors`, native fg/bg/cursor, background) to the live
`terminalView` — the same path pinch-to-zoom already exercises live.

Out of scope: live font/size switching (font stays in the host/group editor;
size stays in the editor + pinch-zoom), and propagating a change to *other*
already-open sessions of the same host.

## Decisions

| Area | Decision |
|---|---|
| What changes live | Theme only |
| Persistence | Persist to `Host.themeID` (becomes the saved default) |
| Entry point | A palette button in the terminal top bar's trailing button row |
| Picker surface | A `.medium`-detent sheet listing the curated presets with live `ThemePreviewRow` swatches; tap applies instantly |
| Inherit option | A "Default (inherit)" row (sets `themeID = nil`) restoring group/global resolution |
| Active indicator | Checkmark on the currently **resolved** theme |

## 1. Model: `TerminalSession.setTheme(id:)`

Add one method to `TerminalSession` (`@MainActor @Observable`), which already
owns `host`, `modelContext`, and `applyAppearance()`:

```swift
/// Change this session's theme live and persist it as the host's default.
/// `nil` clears the host override so the theme resolves from the group/global
/// default again. Applies immediately via the existing appearance path.
func setTheme(id: String?) {
    host.themeID = id
    try? modelContext.save()
    applyAppearance()
}
```

- Writing `host.themeID` and saving makes the change the host's saved default
  (an explicit host-level override of any group inheritance), consistent with
  the host editor's Theme picker, which writes the same field.
- `applyAppearance()` re-resolves `EffectiveHostSettings` and re-applies to the
  live terminal — no reconnect.
- Font/size are untouched; this only sets `themeID`.

## 2. UI: top-bar palette button

In `SessionTabsView.topBar`, add a button to the existing trailing `HStack`
(alongside the AI ✦, new-session +, snippet, and minimize buttons), shown only
when there is an active session:

- Label: `Image(systemName: "paintpalette")`, accessibility label
  "Terminal Theme".
- Disabled when `session.status != .connected` (matches the snippet menu's
  gating; theming a dead terminal is meaningless).
- Tapping presents the theme picker sheet (§3) for the active session.

## 3. UI: theme picker sheet

New view `ThemePickerSheet` (its own file), presented via `.sheet(item:)` keyed
to the session being themed, at `.presentationDetents([.medium])`:

- A `List` with:
  - A **"Default (inherit)"** row at the top → `session.setTheme(id: nil)`.
  - One row per `TerminalTheme.all` preset, each showing the theme name and a
    live `ThemePreviewRow(themeID: theme.id, fontID: <resolved font id>)` so the
    swatch matches the session's actual font. Tapping →
    `session.setTheme(id: theme.id)`.
- A checkmark (`checkmark` / `.overlay` trailing accessory) marks the row whose
  id equals the currently **resolved** theme id
  (`EffectiveHostSettings.resolve(host: session.host).themeID`). For the
  "Default (inherit)" row, it is checked when `session.host.themeID == nil`.
- Tapping a row applies **immediately** (live + persisted) and leaves the sheet
  open so the user can compare; they dismiss when satisfied. Because apply is
  live, the terminal behind/around the medium sheet re-themes in real time.

The sheet consumes the `@Observable` session directly; reading
`session.host.themeID` in its body keeps the checkmark in sync as selections are
made.

## 4. HIG conformance

- Standard, discoverable toolbar affordance (a labeled icon button in the
  existing control row); no hidden gestures.
- The picker is a standard sheet with a medium detent, previews before commit,
  and a clear active-state checkmark.
- Instant, reversible feedback: any pick can be undone by choosing another theme
  or "Default (inherit)".

## 5. Testing

The meaningful behavior is a SwiftData write + UIKit re-apply on a live
`TerminalView`, none unit-testable: instantiating a `TerminalSession` resolves
`@Model` relationships in `init`, which hangs the iOS 26.5 simulator in unit
tests (see `pockterm-swiftdata-test-hangs`); `setTheme` both writes a `@Model`
and calls into SwiftTerm.

- Existing `TerminalTheme` catalog tests and `EffectiveHostSettings` appearance
  resolution tests stay green (unchanged), covering the id lookup and resolution
  the checkmark and preview rely on.
- Simulator `verify` + on-device: open a session, open the theme picker, pick a
  theme → confirm the live terminal re-themes instantly and the checkmark
  moves; reconnect the host → confirm the picked theme persisted; pick "Default
  (inherit)" → confirm it reverts to the resolved default.

## Non-goals

- Live font or size switching in-session (editor + pinch-zoom own those).
- Updating other already-open sessions of the same host (they re-resolve on
  their next reconnect — same as today's editor-vs-open-session behavior).
- A new theme catalog or custom themes (reuses the existing curated presets).
