# Pockterm — Command Suggestions & AI Assistant Design

**Date:** 2026-07-05
**Status:** Approved
**Scope:** Two independent features, built in sequence.

## Decisions (locked)

- **Sequence:** command suggestions first (Phase 6), AI assistant second (Phase 7).
- **AI "sees the screen"** by receiving the terminal's on-screen **text**, not screenshots.
- **AI auth:** **BYO API keys only** for OpenAI, Anthropic, and OpenRouter — stored in
  the iOS Keychain via `SecretStore`. No subscription/OAuth login (not officially
  available to third-party apps for Anthropic/OpenAI; only OpenRouter offers a
  sanctioned OAuth, and the user chose keys-only for simplicity).
- **AI file context:** the user can **add and remove files** to include as context.

---

## Phase 6 — Command suggestions (Termius-style)

**Goal:** As the user types in the terminal, a scrollable **suggestion strip** appears
above the keyboard; tapping a suggestion inserts the rest of the command.

### Sources (ranked)
1. **Per-host command history** — new `CommandHistory` SwiftData model
   (`hostID`, `command`, `lastUsedAt`, `count`).
2. **Snippets** — reuse the Phase-2 `Snippet` model.
3. **Common shell commands** — a built-in static list, used as fallback.

### Current-input tracking (heuristic)
`TerminalSession` maintains a "typed line" reconstructed from outgoing keystrokes:
append printable bytes, handle Backspace (0x7f/0x08), reset on Enter (\r/\n). On Enter,
the completed line (trimmed, non-empty) is recorded into `CommandHistory` for the host.
This is a heuristic — remote-side line editing (arrow keys, Ctrl-R, multi-line) can
desync it; it re-syncs on the next Enter. Pure prefix matching keeps it predictable.

### Matching & UI
- Prefix-match the typed line (case-sensitive on the command token) against the three
  sources; dedupe by command text; rank history/snippets before common commands, then by
  recency/frequency; cap at 8.
- Suggestion strip: horizontal `ScrollView` of chips in the terminal's bottom bar, shown
  only when the typed line is non-empty and there are matches. Tapping a chip sends the
  completion suffix (the part after the typed prefix); it does not auto-send Enter.
- Hidden while a modifier (from the native bar) is mid-sequence is out of scope — the
  strip simply reflects the typed-line model.

### Out of scope (YAGNI)
Fuzzy/subsequence matching, argument/flag/path completion, server-side shell integration.

### Testable units
- `SuggestionEngine.suggestions(for:history:snippets:common:)` (pure, TDD).
- `TypedLineTracker.consume(_:) -> String?` (pure keystroke → line model, TDD).

---

## Phase 7 — AI assistant (design; built after Phase 6)

**Goal:** An in-app assistant that reads the current terminal context and suggests or
explains commands, using the user's own API key.

### Providers & keys
- `AIProvider` enum: `openai`, `anthropic`, `openRouter`.
- Per-provider API key stored in the Keychain (`SecretStore`); a Settings screen to add,
  test, and remove keys, and to pick the active provider + model (sensible defaults:
  Anthropic → `claude-opus-4-8`; others → a documented default).
- All three are HTTPS chat APIs; a small `AIClient` protocol with one impl per provider.
  Anthropic uses `POST /v1/messages` (streaming). Requests stream responses.

### Context
- **Terminal text:** the visible buffer (and optionally recent scrollback) of the active
  session is included as context.
- **Files:** the user can attach/detach files as additional context — remote files via
  the existing SFTP browser and/or local files via the document picker. Attached file
  contents (size-capped) are included in the prompt; a chip list shows attachments with a
  remove control.

### UI
- A chat surface reachable from the terminal (and/or a tab): message history, streaming
  responses, an attachments row, and a "run this command" affordance that sends a
  suggested command into the active session.

### Security & privacy
- Keys never leave the device except to the chosen provider's API. Terminal text and
  attached files are sent to that provider when the user asks — the assistant screen
  states this plainly. Local-only otherwise (no Pockterm backend).

### Testable units
- Request/response encoding per provider (pure, against fixtures).
- Attachment context assembly + size capping (pure).

---

## Success criteria

- Phase 6: typing `gi` after having run `git status` shows `git status` in the strip;
  tapping it inserts `t status`; the finished command is remembered per host.
- Phase 7: with a valid key, the assistant answers a question about the current terminal
  output, and a suggested command can be inserted into the session.
