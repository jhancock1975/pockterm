# Phase 6: Command Suggestions — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A scrollable suggestion strip above the keyboard that offers command completions from per-host history, snippets, and common commands; tapping one inserts the remaining text.

**Architecture:** Pure logic (`TypedLineTracker`, `SuggestionEngine`) is TDD'd. `TerminalSession` reconstructs the typed line from outgoing keystrokes, records finished commands into a `CommandHistory` SwiftData model, and publishes the live suggestion list. `SessionTabsView` renders the strip.

**Tech Stack:** SwiftUI, SwiftData. No new packages.

## Global Constraints

- Same as prior phases: iOS 26.5+, Swift 5 mode, synchronized folder auto-compiles app files; new TEST files need `ruby scripts/setup_project.rb`.

---

### Task 1: TypedLineTracker (pure, TDD)

**Files:**
- Create: `pockterm/Suggestions/TypedLineTracker.swift`
- Test: `pocktermTests/TypedLineTrackerTests.swift`

**Interfaces:**
- `struct TypedLineTracker { private(set) var line: String; mutating func consume(_ bytes: [UInt8]) -> String? }`
  - Appends printable ASCII (0x20–0x7e) to `line`; Backspace (0x7f or 0x08) removes the last char; Enter (0x0a or 0x0d) returns the trimmed line if non-empty (else nil) and resets. Other control bytes reset `line` to "" (conservative: unknown editing invalidates the model).

- [ ] **Step 1: Failing test** — typing "git status" then Enter returns "git status" and resets `line` to ""; a Backspace after "gitx" yields line "git"; a bare Enter returns nil; an arrow-key escape sequence (`0x1b 0x5b 0x41`) resets `line`.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `"Add TypedLineTracker for terminal input reconstruction"`.

---

### Task 2: CommandHistory model + CommonCommands

**Files:**
- Create: `pockterm/Model/CommandHistory.swift`
- Create: `pockterm/Suggestions/CommonCommands.swift`
- Modify: `pockterm/App/AppContainer.swift` + every test `ModelContainer(for:)`
- Test: `pocktermTests/CommandHistoryModelTests.swift`

**Interfaces:**
- `@Model final class CommandHistory { var id: UUID; var hostID: UUID; var command: String; var lastUsedAt: Date; var count: Int }`
- `enum CommonCommands { static let all: [String] }` — a curated static list (`ls`, `cd`, `git status`, `sudo`, `grep`, `tail -f`, …).

- [ ] **Step 1: Failing test** — persist a `CommandHistory` row and read back `command`/`count`.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** model + list; register `CommandHistory.self` in `AppContainer` and all test containers.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `"Add CommandHistory model and common-commands list"`.

---

### Task 3: SuggestionEngine (pure, TDD)

**Files:**
- Create: `pockterm/Suggestions/SuggestionEngine.swift`
- Test: `pocktermTests/SuggestionEngineTests.swift`

**Interfaces:**
- `struct Suggestion: Equatable { let text: String; let kind: Kind /* history, snippet, common */ }`
- `enum SuggestionEngine { static func suggestions(prefix: String, history: [(command: String, count: Int, lastUsedAt: Date)], snippets: [String], common: [String], limit: Int = 8) -> [Suggestion] }`
  - Empty prefix → `[]`. Prefix-match (`hasPrefix`) each source; a source item equal to the prefix is excluded (nothing to complete). Dedupe by `text` keeping the highest-priority kind (history > snippet > common). Order: history (by count desc, then lastUsedAt desc), then snippets (input order), then common (input order). Cap at `limit`.

- [ ] **Step 1: Failing test** — prefix "gi" with history `[("git status",3,…),("git push",1,…)]`, snippets `["gitk"]`, common `["git"]` → `[git status, git push, gitk]` in that order (the bare "git" common item that equals a prefix-of but isn't equal to "gi" is included only if it starts with "gi" — it does, so it appears after, deduped if already present); prefix equal to a command excludes that exact command; empty prefix → `[]`; limit respected.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `"Add SuggestionEngine prefix matcher"`.

---

### Task 4: Wire into TerminalSession

**Files:**
- Modify: `pockterm/Features/Terminal/TerminalSession.swift`

**Interfaces:**
- Add `var suggestions: [Suggestion] = []` (observable) and a private `TypedLineTracker`.
- In `handleInput`, before sending: feed bytes to the tracker; if it returns a finished line, upsert `CommandHistory` for `host.id` (increment `count`, set `lastUsedAt`) and clear suggestions; otherwise recompute `suggestions` from the tracker's `line` via `SuggestionEngine`, reading the host's history + all snippets + `CommonCommands.all`.
- Add `func applySuggestion(_ s: Suggestion)`: compute the completion suffix (`s.text` minus the current typed prefix) and `sendKeys(Array(suffix.utf8))`; the tracker consumes those same bytes so its `line` stays in sync (feed the suffix through the tracker too).

- [ ] **Step 1: Implement** the wiring; fetch history via the session's `modelContext`.
- [ ] **Step 2: Build** for simulator; verify compiles.
- [ ] **Step 3: Commit** `"Wire command history and suggestions into TerminalSession"`.

---

### Task 5: Suggestion strip UI

**Files:**
- Create: `pockterm/Features/Terminal/SuggestionStrip.swift`
- Modify: `pockterm/Features/Terminal/SessionTabsView.swift`

**Interfaces:**
- `SuggestionStrip(suggestions:onTap:)` — a horizontal `ScrollView` of chips (icon per kind), hidden when empty; tapping calls `onTap(suggestion)`.
- In `sessionContent`, place the strip directly above the terminal's bottom edge for the active session, wired to `session.suggestions` and `session.applySuggestion`.

- [ ] **Step 1:** Build `SuggestionStrip`.
- [ ] **Step 2:** Wire into `SessionTabsView`.
- [ ] **Step 3:** Build for simulator; run unit tests; build/install/launch on device `<DEVICE_UDID>`.
- [ ] **Step 4: Commit** `"Add command-suggestion strip to the terminal"`.

---

## Self-Review notes

- **Spec coverage:** strip UI (Task 5) ✓; sources history/snippets/common (Tasks 2,3) ✓; heuristic typed-line tracking + history recording (Tasks 1,4) ✓; tap inserts suffix without auto-Enter (Task 4) ✓.
- **Deferred (per spec):** fuzzy matching, argument/path completion, shell integration.
