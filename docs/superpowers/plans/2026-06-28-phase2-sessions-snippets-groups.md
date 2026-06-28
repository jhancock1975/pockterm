# Phase 2: Sessions, Snippets, Groups, Search & Import — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Extend the Phase 1 SSH terminal into a Termius-grade organizer: multiple concurrent tabbed sessions, reusable snippets (incl. per-host startup), nested groups with setting inheritance, host search/favorites/recents, and `~/.ssh/config` import.

**Architecture:** New SwiftData models (`Group`, `Snippet`) plus additive fields on `Host`. Pure-logic units (group inheritance resolution, ssh_config parsing) are TDD'd against in-memory stores. A `SessionManager` owns multiple live `SSHEngine`/terminal pairs surfaced through a tabbed terminal container. UI features are device-verified.

**Tech Stack:** Same as Phase 1 (SwiftUI, SwiftData, Citadel, SwiftTerm). No new packages.

## Global Constraints

- Same as Phase 1: iOS 26.5+, Swift 5 mode, app target `pockterm`, secrets only via `SecretStore`.
- New app `.swift` files auto-compile via the synchronized folder group; new TEST files require `ruby scripts/setup_project.rb`.
- Host-key validation stays `acceptAnything()` this phase (NIOSSH exposes no public host-key serialization); add a visible "unverified" indicator. Real TOFU is deferred to the libssh2 evaluation.

---

### Task 1: Extend models — Group, Snippet, Host fields

**Files:**
- Create: `pockterm/Model/Group.swift`
- Create: `pockterm/Model/Snippet.swift`
- Modify: `pockterm/Model/Host.swift`
- Modify: `pockterm/App/AppContainer.swift` (register new models)
- Test: `pocktermTests/GroupModelTests.swift`

**Interfaces:**
- Produces:
  - `@Model final class Group { var id: UUID; var name: String; var parent: Group?; var defaultIdentity: Identity?; var defaultPort: Int? }`
  - `@Model final class Snippet { var id: UUID; var label: String; var command: String }`
  - `Host` gains: `var group: Group?`, `var isFavorite: Bool`, `var lastConnectedAt: Date?`.

- [ ] **Step 1: Failing test** — `pocktermTests/GroupModelTests.swift`

```swift
import Testing
import SwiftData
@testable import pockterm

@MainActor
@Test func hostBelongsToGroupAndFavorite() throws {
    let c = try ModelContainer(for: Host.self, Identity.self, SSHKeyRecord.self,
                               KnownHostRecord.self, Group.self, Snippet.self,
                               configurations: .init(isStoredInMemoryOnly: true))
    let ctx = c.mainContext
    let g = Group(name: "prod")
    let h = Host(label: "web", address: "1.1.1.1")
    h.group = g
    h.isFavorite = true
    ctx.insert(h)
    try ctx.save()
    let fetched = try ctx.fetch(FetchDescriptor<Host>())
    #expect(fetched.first?.group?.name == "prod")
    #expect(fetched.first?.isFavorite == true)
}
```

- [ ] **Step 2: Run, verify fail** (`Group` not found).
- [ ] **Step 3: Implement** `Group`, `Snippet`, add Host fields, register all six models in `AppContainer` and in every `ModelContainer(for:)` test call.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `"Add Group and Snippet models; host group/favorite/recents fields"`.

---

### Task 2: Group setting inheritance (pure logic, TDD)

**Files:**
- Create: `pockterm/Vault/EffectiveHostSettings.swift`
- Test: `pocktermTests/InheritanceTests.swift`

**Interfaces:**
- Produces: `struct EffectiveHostSettings { let port: Int; let identity: Identity? }` and
  `static func resolve(host: Host) -> EffectiveHostSettings` — host value wins; else nearest ancestor group's default (walking `parent` chain); else port 22 / nil identity.

- [ ] **Step 1: Failing test** covering: host overrides group; group default used when host unset; nested parent group default used when nearest group unset; default port 22 when nothing set.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** the parent-walk resolution.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `"Add group setting inheritance resolution"`.

---

### Task 3: ssh_config parser (pure logic, TDD)

**Files:**
- Create: `pockterm/Import/SSHConfigParser.swift`
- Test: `pocktermTests/SSHConfigParserTests.swift`

**Interfaces:**
- Produces: `struct ParsedHost { let alias: String; let hostName: String?; let user: String?; let port: Int? }` and
  `enum SSHConfigParser { static func parse(_ text: String) -> [ParsedHost] }`.
- Handles `Host` blocks, `HostName`, `User`, `Port`; ignores comments/unknown keys; case-insensitive keys; skips wildcard-only `Host *`.

- [ ] **Step 1: Failing test** with a multi-host config sample asserting parsed aliases, hostnames, users, ports, and that `Host *` is skipped.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** line-based parser.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `"Add ssh_config parser"`.

---

### Task 4: Import UI (paste / file)

**Files:**
- Create: `pockterm/Features/Import/ImportConfigView.swift`
- Modify: `pockterm/App/RootTabView.swift` (Settings tab → entry point) or Hosts toolbar.

**Interfaces:**
- Consumes: `SSHConfigParser` (Task 3), models. Produces hosts (and identities for distinct users) from pasted/imported text; shows a preview list with per-row include toggles before saving.

- [ ] **Step 1:** Build a paste-text + `.fileImporter` screen; parse on change; preview parsed hosts.
- [ ] **Step 2:** On import, create `Host` rows (and a key-less password identity per distinct user, secret left empty for the user to fill).
- [ ] **Step 3:** Build for simulator; verify compiles.
- [ ] **Step 4: Commit** `"Add ssh_config import screen"`.

---

### Task 5: Snippets feature

**Files:**
- Create: `pockterm/Features/Snippets/SnippetsListView.swift`
- Create: `pockterm/Features/Snippets/SnippetEditorView.swift`
- Modify: `pockterm/App/RootTabView.swift` (replace Snippets placeholder)
- Modify: `pockterm/Features/Terminal/TerminalSessionView.swift` (run-snippet menu)

**Interfaces:**
- Consumes: `Snippet` (Task 1), active `SSHEngine`. Produces: snippet CRUD; a terminal toolbar menu listing snippets that, when tapped, sends `command + "\n"` to the live session.

- [ ] **Step 1:** Snippets list + editor (label, command).
- [ ] **Step 2:** Terminal toolbar menu → send snippet bytes to engine.
- [ ] **Step 3:** Build for simulator; verify compiles.
- [ ] **Step 4: Commit** `"Add snippets feature with terminal run menu"`.

---

### Task 6: Groups feature + host assignment

**Files:**
- Create: `pockterm/Features/Groups/GroupsListView.swift`
- Create: `pockterm/Features/Groups/GroupEditorView.swift`
- Modify: `pockterm/Features/Hosts/HostEditorView.swift` (group picker + favorite toggle)
- Modify: `pockterm/Features/Hosts/HostsListView.swift` (section by group)

**Interfaces:**
- Consumes: `Group` (Task 1), `EffectiveHostSettings` (Task 2). Produces: group CRUD with parent + default identity/port; host editor assigns group & favorite; host list groups rows by group name.

- [ ] **Step 1:** Group list + editor.
- [ ] **Step 2:** Host editor group picker + favorite toggle; connect path uses `EffectiveHostSettings.resolve` for port/identity.
- [ ] **Step 3:** Host list sectioned by group.
- [ ] **Step 4:** Build for simulator; verify compiles.
- [ ] **Step 5: Commit** `"Add groups with inheritance and host assignment"`.

---

### Task 7: Search, favorites, recents

**Files:**
- Modify: `pockterm/Features/Hosts/HostsListView.swift`

**Interfaces:**
- Consumes: `Host.isFavorite`, `Host.lastConnectedAt`. Produces: `.searchable` filtering by label/address; a Favorites section; a Recents section sorted by `lastConnectedAt`; connect sets `lastConnectedAt = .now`.

- [ ] **Step 1:** Add `@State searchText` + `.searchable`; filter hosts.
- [ ] **Step 2:** Favorites + Recents sections; set `lastConnectedAt` on connect.
- [ ] **Step 3:** Build for simulator; verify compiles.
- [ ] **Step 4: Commit** `"Add host search, favorites, and recents"`.

---

### Task 8: Multiple concurrent sessions + tabs

**Files:**
- Create: `pockterm/Features/Terminal/SessionManager.swift`
- Create: `pockterm/Features/Terminal/TerminalSession.swift`
- Create: `pockterm/Features/Terminal/SessionTabsView.swift`
- Modify: `pockterm/Features/Hosts/HostsListView.swift` (open via SessionManager)
- Modify: `pockterm/Features/Terminal/TerminalSessionView.swift` (refactor to drive one `TerminalSession`)

**Interfaces:**
- Produces:
  - `@MainActor @Observable final class TerminalSession { let id: UUID; let host: Host; let engine: SSHEngine; var title: String; var status }`
  - `@MainActor @Observable final class SessionManager { var sessions: [TerminalSession]; var active: TerminalSession.ID?; func open(host:secretStore:); func close(_:) }`
  - `SessionTabsView` — a tab strip over the active session's terminal; "+" returns to host picker.

- [ ] **Step 1:** Extract `TerminalSession` (one engine + terminal + connect logic from Phase 1's view).
- [ ] **Step 2:** `SessionManager` holding multiple sessions; tab strip UI; switching keeps background sessions alive.
- [ ] **Step 3:** Host list "connect" adds a session and presents `SessionTabsView`.
- [ ] **Step 4:** Build for simulator; run unit tests; build/install/launch on device id `00008150-00117DD83C9A401C`.
- [ ] **Step 5: Commit** `"Add multi-session terminal with tabs"`.

---

## Self-Review notes

- **Spec coverage (Phase 2):** tabs/multiple sessions (Task 8) ✓; snippets + startup (Task 5; per-host startup already on `Host.startupSnippet` from Phase 1, sent on connect) ✓; groups + inheritance (Tasks 1,2,6) ✓; search/favorites/recents (Task 7) ✓; ssh_config import (Tasks 3,4) ✓.
- **Split panes:** Termius supports split; deferred to a Phase 2.x follow-up if tabbing lands first (YAGNI for initial Phase 2 cut — tabs deliver the multi-session value).
- **Host-key TOFU:** intentionally deferred to the libssh2 evaluation; visible unverified indicator added. Tracked as the standing limitation.
