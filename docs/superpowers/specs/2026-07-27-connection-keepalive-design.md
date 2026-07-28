# Configurable Connection Keep-Alive

**Date:** 2026-07-27
**Status:** Approved design, ready for planning

## Summary

Let users control how long an **idle** SSH session stays connected. pockterm
currently sends no keep-alives, so idle sessions are dropped by the server or
NAT after a few minutes. This feature adds an SSH keep-alive that holds an idle
session open for a configurable duration, then deliberately closes it and shows
a disconnect screen linking to the setting.

Settings are **per-host with group inheritance and a global default** (reusing
the `EffectiveHostSettings` pattern). The default is **Off**, which reproduces
today's behavior exactly (no keep-alive, no client-side close).

Out of scope: any change to how *active* sessions behave; power/battery tuning
beyond a fixed keep-alive interval; keep-alive for SFTP/port-forward-only
connections (this covers interactive terminal sessions).

## Decisions

| Area | Decision |
|---|---|
| Meaning | Keep-alive: hold an **idle** session open longer (not security auto-logout) |
| Scope | Per-host override → nearest group default → global default → built-in Off |
| Default | **Off** (0) — behaves exactly as today |
| Options | Off, 5, 15, 30, 60 minutes |
| Keep-alive interval | Fixed **60s** while idle (not user-configurable) |
| Idle definition | No user keystrokes; any input resets the idle clock |
| At the limit | Stop keep-alives, disconnect, set status `.idleDisconnected` |
| Disconnect UI | `ContentUnavailableView("Disconnected due to inactivity")` + a button deep-linking to Settings → Connection |
| Personalization | Set the global default to **30 minutes** for this user |

## 1. Data model & resolution

Mirrors the port/identity/appearance inheritance already in
`EffectiveHostSettings`: a non-inherit host value wins; else the nearest
ancestor group that defines it; else the global default; else built-in Off.

New fields:

- `Host.keepAliveSeconds: Int` — inline default `= 0` (0 = inherit sentinel;
  inline default is **required** for SwiftData lightweight migration of a
  non-optional field, same lesson as `Host.fontSize`).
- `HostGroup.defaultKeepAliveSeconds: Int?` — `nil` = not set at this group.
- New singleton `@Model ConnectionSettings` holding
  `defaultKeepAliveSeconds: Int = 0`, accessed via a
  `static func single(in:) -> ConnectionSettings` dedupe accessor (copy the
  proven pattern from `AISettings.single(in:)`).

Resolution order for a host's effective keep-alive seconds:
`host (if != 0)` → `nearest group with non-nil default` → `global
ConnectionSettings.defaultKeepAliveSeconds (if != 0)` → `0 (Off)`.

Pure function (unit-tested with plain values, no `@Model` walking):

```
static func resolveKeepAlive(
    hostValue: Int, chain: [Int?], globalDefault: Int
) -> Int
```

where `hostValue`/elements use `0`/`nil` as "not set". The `@MainActor
resolve(host:)`-style wrapper walks `host.group` ancestry and reads the global
row; it is exercised only by the simulator smoke run, not unit tests.

### Selectable values

`0` (Off), `300`, `900`, `1800`, `3600` seconds. A shared
`KeepAliveOption` enum/list provides the (seconds, label) pairs for the
pickers so Settings, host editor, and group editor stay consistent.

## 2. Keep-alive mechanism

While a session is connected **and idle**, a repeating 60s timer sends an SSH
keep-alive over the live connection so the server/NAT does not drop it.

- Mechanism: send an SSH keep-alive request on the existing connection. The
  exact call (Citadel API vs. dropping to the underlying NIOSSH channel with a
  `keepalive@openssh.com` global request) is resolved during planning against
  the Citadel version in use. **Fallback** if no clean keep-alive API exists:
  send a zero-width no-op over the channel that does not disturb the shell.
  The plan must confirm the chosen mechanism actually produces on-wire traffic.
- The timer lives on `TerminalSession` (which owns `engine`/`terminalView`),
  runs on the main actor, and is invalidated on disconnect/close.
- When resolved keep-alive is `0` (Off), no timer is scheduled — zero behavior
  change from today.

## 3. Idle tracking & disconnect

`TerminalSession` tracks `lastActivityAt`, reset in `handleInput(_:)` (already
the single choke point for user keystrokes) and on connect.

- A check (driven by the same 60s timer) compares idle elapsed time against the
  resolved hold-time. When idle ≥ hold-time, the session stops the keep-alive,
  calls the existing `disconnect()` path, and sets a new status case
  `.idleDisconnected` (added to `TerminalSession.Status`).
- Idle math is factored into a pure helper for testing, e.g.
  `shouldIdleDisconnect(idleSeconds: Int, holdSeconds: Int) -> Bool`
  (`holdSeconds == 0` → always false).

## 4. UI

- **Settings tab → new "Connection" screen** (`SettingsHomeView` currently
  lives in `RootTabView.swift`; add a `NavigationLink` row to a new
  `ConnectionSettingsView`). It has one picker bound to
  `ConnectionSettings.defaultKeepAliveSeconds` over `KeepAliveOption` values.
- **Host editor** (`HostEditorView`, Connection section) and **Group editor**
  (`GroupEditorView`): a "Keep-alive" picker. Host offers
  "Default (inherit)" (`0`) plus the options; group offers "None" (`nil`) plus
  the options — the same optional-tag idiom used by the appearance pickers.
- **Inactivity disconnect**: in `SessionTabsView.sessionContent`, add a
  `case .idleDisconnected` alongside `.closed`, rendering
  `ContentUnavailableView("Disconnected due to inactivity", systemImage:
  "moon.zzz", description: …)` with an action button
  **"Change how long sessions stay connected"**. The button switches to the
  Settings tab and navigates to the Connection screen (via a shared tab
  selection / navigation-path binding on the root).

## 5. Testing

Pure-logic unit tests (swift-testing, via `scripts/test.sh`, no `@Model` walk):

- `resolveKeepAlive`: host value wins; nearest-group inheritance; global
  default used when host/groups unset; Off when nothing set; `0` sentinel.
- `shouldIdleDisconnect`: below hold-time → false; at/above hold-time → true;
  `holdSeconds == 0` → always false.
- `KeepAliveOption` list: expected seconds/labels; Off present and first.

Simulator `verify` (cannot be unit-tested): with a short hold-time, confirm an
idle session keep-alives, then transitions to the inactivity-disconnect screen,
and that the button lands on Settings → Connection. Confirm Off = no behavior
change.

## Non-goals

- Security idle auto-logout framing (this is keep-alive/hold, not forced
  logout).
- Per-session UI to change the timer mid-session.
- Configurable keep-alive interval (fixed 60s).
- Keep-alive for non-interactive (SFTP-only / forward-only) connections.
