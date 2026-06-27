# Pockterm — Termius Functional Clone Design

**Date:** 2026-06-27
**Status:** Approved
**Scope:** Single-device (local-only) functional clone of the Termius iPhone app.

## Goal

Build a precise functional clone of Termius for iPhone: every user-facing
feature, organized the way Termius organizes it. "Functional clone" means
feature parity from the user's perspective, not a reimplementation of
Termius's internals.

## Decisions (locked)

1. **Local-only.** No account, no cloud sync, no teams. All data lives on the
   device. Cloud sync / teams is explicitly a *future, separate* project and is
   out of scope here.
2. **Protocol order.** SSH + SFTP + port forwarding ship first; Mosh, Telnet,
   serial, and proxy-jump chains follow in a later phase. Nothing is dropped —
   only sequenced.
3. **Phased & runnable.** The app builds and runs on a physical iPhone after
   every phase.

## Platform / Tech (fidelity-relevant only)

- **iOS app:** existing `pockterm.xcodeproj`, SwiftUI, target iOS 26+, bundle id
  `John-Hancock.pockterm`, team `5H22F8M69N`, automatic signing.
- **Terminal emulator:** SwiftTerm (xterm-256color, ANSI/truecolor, resize).
- **SSH transport:** SwiftNIO SSH / Citadel (pure Swift). Swap the SSH layer to
  libssh2 only if a specific auth/key feature proves unsupported.
- **Persistence:** SwiftData for structured records.
- **Secrets:** Keychain behind a `SecretStore` protocol (testable; real Keychain
  can't be unit-tested in SwiftPM iOS tests). Biometric (Face ID / Touch ID)
  gate on the vault.

## Architecture — functional modules

Each module has one clear purpose and a defined interface so it can be built and
tested independently.

### 1. Vault / Data layer
- Models: `Host`, `Group`, `Identity`, `SSHKey`, `Snippet`, `KnownHost`,
  `PortForward`, `TerminalTheme`.
- SwiftData persistence for non-secret fields.
- `SecretStore` protocol (Keychain-backed in production, in-memory for tests)
  for passwords, private keys, and passphrases.
- Biometric lock controlling access to the vault on app foreground.

### 2. SSH engine
- Connection / channel / PTY lifecycle.
- Auth: password, public-key, keyboard-interactive, agent.
- Known-hosts: trust-on-first-use, fingerprint verification, mismatch warning.
- Keep-alive and auto-reconnect.

### 3. Terminal UI
- SwiftTerm-backed terminal view bridged to SwiftUI.
- Accessory key bar: Esc, Ctrl, Alt, Tab, arrows, Fn, common keys.
- Hardware keyboard support.
- Themes/color schemes, font family + size, cursor style.
- Scrollback, in-terminal search, copy/paste, selection, URL detection.

### 4. SFTP
- Dual-pane browser (local ⇄ remote).
- Upload/download with a transfer queue + progress.
- Operations: rename, delete, mkdir, chmod, permissions.

### 5. Port forwarding
- Local, remote, and dynamic (SOCKS) tunnels.
- Live status per tunnel; start/stop.
- Agent forwarding.

### 6. App shell / navigation
- Termius-style tab bar: Hosts · Snippets · Keychain · Port Forwarding ·
  Terminal · Settings.
- Host editor (full per-host config), Group management with setting
  inheritance, search, favorites, recents.

## Feature inventory (parity target)

**Connections & protocols:** SSH, Mosh, Telnet, local shell, serial; proxy-jump
/ bastion chains; port forwarding (local/remote/dynamic); SSH agent + agent
forwarding; keep-alive / auto-reconnect.

**Hosts & organization:** hosts with full per-host config (address, port,
identity, startup snippet, env, backspace mode, terminal type); nested groups
with inheritance; tags; search; recents/favorites; import from `~/.ssh/config`.

**Credentials & keys:** identities (username/password/key bundles); SSH keys —
generate (Ed25519/RSA/ECDSA), import, export, passphrase; known-hosts
management; biometric vault lock.

**Terminal:** tabs + multiple concurrent sessions, split panes; accessory key
bar + hardware keyboard; color schemes/themes, font + size, cursor styles;
scrollback, search, copy/paste, selection, URL detection; snippets + startup
snippets.

**SFTP / files:** dual-pane browser; upload/download; rename/delete/chmod/mkdir;
transfer queue.

**Out of scope (future, separate project):** account, end-to-end-encrypted
cross-device sync, team sharing, audit.

## Phased delivery

- **Phase 1 — Core SSH terminal (runnable):** app shell + tab nav; Host list &
  editor; Identities; SSH key generate/import (Keychain-secured); known-hosts
  TOFU; SSH connect (password + key auth); SwiftTerm terminal with accessory
  key bar, themes, copy/paste, scrollback. → user can SSH into a real server.
- **Phase 2 — Sessions & snippets:** tabs / multiple concurrent sessions +
  split; Snippets (CRUD/run/startup); Groups with setting inheritance;
  search/favorites/recents; `~/.ssh/config` import.
- **Phase 3 — SFTP:** dual-pane browser, upload/download queue,
  chmod/rename/delete/mkdir.
- **Phase 4 — Port forwarding:** local/remote/dynamic tunnels + agent
  forwarding, status UI.
- **Phase 5 — Remaining protocols & polish:** Mosh, Telnet, serial, proxy-jump
  chains; full settings parity; biometric lock hardening.

## Success criteria

- Each phase produces an app that builds, signs, installs, and launches on the
  physical iPhone.
- Phase 1 success: create a host with a key or password identity, connect over
  real SSH, run an interactive shell with a working terminal, disconnect — all
  on-device with secrets stored in the Keychain.
- Final success: every feature in the inventory above is present and usable.

## Testing strategy

- Unit tests for the Vault/Data layer and `SecretStore` against the in-memory
  store; key generation/parsing round-trips; known-hosts logic; `~/.ssh/config`
  parsing; port-forward config.
- Manual/device verification for terminal rendering, SSH connectivity, SFTP
  transfers, and tunnels (network + PTY behavior can't be meaningfully unit
  tested on-device).
