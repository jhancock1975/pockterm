# Live In-Session Theme Switching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user change a live terminal session's theme from a top-bar control, applying instantly and persisting the choice to the host.

**Architecture:** Add a `setTheme(id:)` method to `TerminalSession` that writes `Host.themeID`, saves, and calls the existing `applyAppearance()` (which already re-themes the live `terminalView`). Add a palette button to the terminal top bar that presents a `ThemePickerSheet` reusing the existing `ThemePreviewRow` and `TerminalTheme.all`.

**Tech Stack:** Swift 6.2, SwiftUI, SwiftData (`@Model`), Observation (`@Observable`), SwiftTerm.

## Global Constraints

- **Persist to the host:** the live change writes `Host.themeID` (an explicit host-level override) and saves the `ModelContext`. `nil` = inherit (clears the override so the theme resolves from group/global). This mirrors the host editor's Theme picker, which writes the same field.
- **Reuse the existing apply path:** live re-theming goes through `TerminalSession.applyAppearance()`. Do NOT reimplement `installColors`/native-color application.
- **Theme only:** set `themeID` only. Do NOT touch `Host.fontID` or `Host.fontSize`.
- **Reuse existing appearance components:** `TerminalTheme.all` (the curated presets, already `Identifiable`), `TerminalTheme.theme(id:)`, `ThemePreviewRow(themeID:fontID:)`, and `EffectiveHostSettings.resolve(host:)`. Do NOT add a new theme catalog.
- **Checkmark = stored selection:** exactly one checkmark, reflecting `Host.themeID` — the "Default (inherit)" row when `themeID == nil`, else the matching preset row. (This refines the spec's "resolved" wording to avoid showing two checkmarks in the inherit case.)
- **No pbxproj edit for the new view:** files added under `pockterm/` auto-include via the `PBXFileSystemSynchronizedRootGroup` (only test files need pbxproj entries). Adding a pbxproj entry would break the build with a duplicate reference.
- **Unit-test constraint:** do NOT add unit tests that instantiate `TerminalSession` (its `init` resolves `@Model` relationships, hanging the iOS 26.5 simulator — see `pockterm-swiftdata-test-hangs`). `setTheme` writes a `@Model` and calls SwiftTerm; it is verified via the simulator `verify` harness. The existing `TerminalTheme` and `EffectiveHostSettings` tests must stay green.
- **Build/test command:** `scripts/test.sh --build` (never plain `xcodebuild test`).

---

### Task 1: `TerminalSession.setTheme(id:)`

**Files:**
- Modify: `pockterm/Features/Terminal/TerminalSession.swift`

**Interfaces:**
- Consumes: existing `host` (a `Host` `@Model`), `modelContext`, and `applyAppearance()`.
- Produces (used by Task 2): `func setTheme(id: String?)`.

**Context:** `TerminalSession` (`@MainActor @Observable final class`) holds `let host: Host`, `let modelContext: ModelContext`, and `func applyAppearance()` which re-resolves `EffectiveHostSettings.resolve(host:)` and applies theme + font to `terminalView`. `Host.themeID` is an optional `String?` (`nil` = inherit).

- [ ] **Step 1: Add `setTheme(id:)`**

Add this method to `TerminalSession` (place it near `applyAppearance()`):

```swift
    /// Change this session's theme live and persist it as the host's default.
    /// `id == nil` clears the host override so the theme resolves from the
    /// group/global default again. Applies immediately via the existing
    /// appearance path — no reconnect. Does not touch font or size.
    func setTheme(id: String?) {
        host.themeID = id
        try? modelContext.save()
        applyAppearance()
    }
```

- [ ] **Step 2: Build and run the existing suite**

Run: `scripts/test.sh --build`
Expected: BUILD SUCCEEDS; all existing tests pass. No new unit tests (see Global Constraints — `TerminalSession` cannot be instantiated in a unit test).

- [ ] **Step 3: Commit**

```bash
git add pockterm/Features/Terminal/TerminalSession.swift
git commit -m "Add TerminalSession.setTheme(id:) for live, persisted theme change"
```

---

### Task 2: `ThemePickerSheet` + top-bar palette button

**Files:**
- Create: `pockterm/Features/Terminal/ThemePickerSheet.swift`
- Modify: `pockterm/Features/Terminal/SessionTabsView.swift`

**Interfaces:**
- Consumes (from Task 1): `session.setTheme(id:)`. Also `session.host.themeID`, `TerminalTheme.all`, `ThemePreviewRow`, `EffectiveHostSettings.resolve(host:).fontID`.
- Produces: `struct ThemePickerSheet: View` taking a `TerminalSession`.

**Context:** `SessionTabsView.topBar` has a trailing `HStack(spacing: 12)` of control buttons (AI ✦ via `Image("sparkles")`, new-session `+`, a snippet `Menu` gated on `session.status == .connected`, and a minimize `chevron.down`). The view already uses `.sheet(item:)` for the assistant (`@State private var assistantSession: TerminalSession?` + `.sheet(item: $assistantSession) { … }`). `TerminalSession` is `Identifiable` (id = UUID) and `@Observable`; `Status` is `Equatable`. `Host` is a SwiftData `@Model`, so reading `session.host.themeID` in a SwiftUI body tracks changes.

- [ ] **Step 1: Create `ThemePickerSheet`**

Create `pockterm/Features/Terminal/ThemePickerSheet.swift`:

```swift
import SwiftUI

/// In-session theme picker: the curated presets with live previews plus a
/// "Default (inherit)" option. Tapping a row applies the theme to the live
/// terminal and persists it to the host via `TerminalSession.setTheme(id:)`.
/// Stays open after a tap so themes can be compared; the checkmark tracks the
/// host's stored selection.
struct ThemePickerSheet: View {
    let session: TerminalSession

    var body: some View {
        // The session's resolved font, so each swatch matches the real terminal.
        let fontID = EffectiveHostSettings.resolve(host: session.host).fontID
        let selected = session.host.themeID   // nil = inherit

        NavigationStack {
            List {
                Button {
                    session.setTheme(id: nil)
                } label: {
                    row(title: "Default (inherit)", checked: selected == nil, preview: nil)
                }
                .buttonStyle(.plain)

                ForEach(TerminalTheme.all) { theme in
                    Button {
                        session.setTheme(id: theme.id)
                    } label: {
                        row(title: theme.name,
                            checked: selected == theme.id,
                            preview: ThemePreviewRow(themeID: theme.id, fontID: fontID))
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle("Theme")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func row(title: String, checked: Bool, preview: ThemePreviewRow?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                if checked {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            preview
        }
        .contentShape(Rectangle())
    }
}
```

Note: `preview` is an optional `ThemePreviewRow?`; SwiftUI renders `nil` as empty, so the inherit row shows no swatch.

- [ ] **Step 2: Add the palette button to the top bar**

In `SessionTabsView.topBar`, inside the trailing `HStack(spacing: 12)`, add this block immediately BEFORE the minimize (`chevron.down`) button:

```swift
                    if let session = manager.active {
                        Button { themingSession = session } label: {
                            Image(systemName: "paintpalette")
                        }
                        .accessibilityLabel("Terminal Theme")
                        .disabled(session.status != .connected)
                    }
```

- [ ] **Step 3: Add the sheet state and presentation**

In `SessionTabsView`, add the state property next to `assistantSession`:

```swift
    @State private var themingSession: TerminalSession?
```

And add this `.sheet(item:)` modifier alongside the existing sheets on the body (e.g. right after the `.sheet(item: $assistantSession) { … }` modifier):

```swift
        .sheet(item: $themingSession) { session in
            ThemePickerSheet(session: session)
        }
```

- [ ] **Step 4: Build and run the suite**

Run: `scripts/test.sh --build`
Expected: BUILD SUCCEEDS; all existing tests pass. No new unit tests (SwiftUI sheet + `@Model` write; see Global Constraints).

- [ ] **Step 5: Commit**

```bash
git add pockterm/Features/Terminal/ThemePickerSheet.swift pockterm/Features/Terminal/SessionTabsView.swift
git commit -m "Add in-session theme picker with top-bar palette button"
```

---

## Verification (after both tasks)

Simulator `verify` harness + on-device, since the `@Model` write and live SwiftTerm re-apply cannot be unit-tested:

1. Open a session and connect.
2. Tap the palette button → the theme sheet appears at medium detent, previews rendered, checkmark on the current selection.
3. Tap a different theme → the live terminal re-themes instantly and the checkmark moves.
4. Dismiss, then disconnect and reconnect the host → confirm the picked theme persisted.
5. Reopen the picker, tap "Default (inherit)" → confirm it reverts to the resolved group/global default and the checkmark moves to the inherit row.
