# Auto-Reconnect, Secure Enclave Keys & Key Bar Discoverability

**Date:** 2026-11-24
**Status:** Draft design, ready for review (builds from issue #39)
**Source:** Feedback from u/ThanhDongNguyen on the r/SideProject launch post
  (https://www.reddit.com/r/SideProject/comments/1y3u8y6/)

## Summary

Phone SSH is mostly quick checks — restart a service, tail a log, open htop
when something is down — so reconnecting matters more than anything else. On
iPhone the connection drops when you switch apps or the network changes. This
spec covers the three items from that feedback, in the order they ship:

1. **Key bar discoverability (1.11, quick win).** The customizable key row
   above the keyboard already exists; the commenter did not know it.
2. **Auto-reconnect into the same tmux session (1.12).** Reconnect on drop
   with backoff, reopen the shell, and optionally re-attach to tmux, so the
   user lands back where they were. This covers most of what full mosh
   would give, without porting a UDP client.
3. **Secure Enclave key generation (after 1.12).** An ECDSA key whose
   private key never leaves the Secure Enclave, unlocked with Face ID.

Out of scope: full mosh support, which stays in Phase 5 of the design doc
(`docs/superpowers/specs/2026-06-27-pockterm-design.md`) — porting the
UDP/SSP client is a much bigger lift than auto-reconnect.

## Decisions

| Area | Decision |
|---|---|
| Order | Key bar (1.11) → auto-reconnect + tmux (1.12) → Secure Enclave key |
| Reconnect default | On for terminal sessions, with a per-host opt-out |
| tmux re-attach | Per-host opt-in setting, off by default |
| tmux command | `tmux new -A -s pockterm` (attach or create session `pockterm`) |
| Reconnect scope (1.12) | Interactive terminal sessions only; SFTP and port forwarding keep `reconnect: .never` for now |
| Secure Enclave key type | `SecureEnclave.P256.Signing` with `.biometryCurrentSet` access control |
| Secure Enclave public key | Export as `ecdsa-sha2-nistp256` for `authorized_keys` / display |

## Verified current state (2026-11-24)

- `pockterm/SSH/SSHEngine.swift:46` — `SSHClient.connect(..., reconnect: .never, ...)`.
  Same `.never` in `pockterm/SFTP/SFTPService.swift:21` and
  `pockterm/Forwarding/PortForwardService.swift:23`.
- `SSHEngine.connect(_:onHostKey:)` builds the auth method from
  `SSHCredentials.authenticationMethod()`; `openShell(cols:rows:onOutput:onClose:)`
  drives the PTY through Citadel `withPTY` and fires `onClose()` when the shell
  ends. That `onClose` is the natural reconnect trigger.
- In-app key generation already exists (Keychain tab → Generate Ed25519 Key,
  `KeyManager.generateEd25519`); import is also supported.
- Key bar customization already exists (`KeyBarSettingsView`, `KeyBarConfig`
  with `defaultsKey "keyBarKeys"` and a `keyBarConfigChanged` notification;
  changes apply to open sessions immediately).
- No `SecureEnclave` usage exists anywhere in the codebase yet.
- `SSHCredentials` uses CryptoKit `Curve25519.Signing.PrivateKey` from a PEM
  seed today; Citadel parses the container on import.
- 1.11 is in Prepare for Submission (App Store Connect, 2026-11-24), so the
  key bar item rides a new 1.11 build, not a separate release.

## 1. Key bar discoverability (1.11)

### Changes

- **Long-press on the key bar opens Key Bar settings.** The gesture target is
  the bar itself, not a single key, so it is discoverable without adding chrome.
- **One-time hint the first time the terminal opens.** A single dismissible
  hint ("Long-press the key row to customize it") shown once, never again
  after dismissal. Do not re-show it on later launches.
- **Help entry.** Add a short entry to Help explaining the key bar is
  customizable (reorder, remove, add keys from the catalogue) and how to reach
  the settings.

### Acceptance

- Long-pressing the bar opens the settings on a fresh install and on an
  existing install.
- The hint appears exactly once per install (persist the shown flag).
- Help entry is reachable from the terminal and from Help search, if Help has one.

## 2. Auto-reconnect into tmux (1.12)

### Behavior

- **Drop detection.** Reconnect is attempted when the shell closes
  unexpectedly (`onClose` from `SSHEngine.openShell` without a user-initiated
  disconnect), when `NWPathMonitor` reports a path change, and when the app
  returns to the foreground with a dead session.
- **Backoff.** Reconnect with exponential backoff (first retry ~1s, cap ~30s,
  give up after N attempts and show the disconnect screen with a manual
  Reconnect button). Never spin a tight reconnect loop against a dead server.
- **Shell reopen.** On a successful reconnect, reopen the shell with the
  session's current size and resume streaming output. Scrollback already on
  screen is kept; output produced while disconnected is not replayed (note
  this in Help — tmux re-attach is what recovers it).
- **tmux re-attach (per-host opt-in).** When enabled for a host, run
  `tmux new -A -s pockterm` as the shell command after reconnect (and on the
  initial connect, so the first session is already inside tmux). Off by
  default; a host without tmux installed must fail soft — fall back to a plain
  shell and say so once, not on every reconnect.
- **Setting inheritance.** Follow the `EffectiveHostSettings` pattern used by
  keep-alive (`docs/superpowers/specs/2026-07-27-connection-keepalive-design.md`):
  per-host override → nearest group default → global default → built-in
  (reconnect on, tmux off). New non-optional `Host` fields need inline
  defaults for SwiftData lightweight migration, same lesson as `Host.fontSize`.
- **User-initiated disconnect stays disconnected.** Tapping Disconnect, or
  closing the session, must never trigger a reconnect.

### Out of scope for 1.12

- Reconnect for SFTP transfers and port forwarding (stay `.never`); a
  transfer cut mid-flight must not silently resume.
- Keep-alive changes (already covered by the 2026-07-27 spec).

### Acceptance

- Kill the network (Airplane Mode on/off) mid-session: the shell reconnects
  on its own and the prompt returns.
- Background the app for 5 minutes, foreground it: session is live again
  without tapping anything.
- With tmux on, disconnect and reconnect: `htop` / the previous shell state
  is still there.
- With tmux on for a host without tmux installed: plain shell, one notice,
  no reconnect loop.
- Disconnect tapped by the user: no reconnect attempt, no banner.

## 3. Secure Enclave key generation (after 1.12)

### Changes

- **Generate** a `SecureEnclave.P256.Signing` private key with access control
  `.biometryCurrentSet` (Face ID / Touch ID, invalidated if biometrics change),
  stored in the Keychain with `kSecAttrTokenIDSecureEnclave`.
- **Export the public key** as `ecdsa-sha2-nistp256` (SSH wire format) for
  display, copying into `authorized_keys`, and the existing key list UI.
- **Use it for auth.** Wire the enclave key into `SSHCredentials` as a new
  credential kind alongside the existing Ed25519 seed and imported PEM keys.
  The private key must never be exportable — signing happens inside the
  enclave per authentication.

### Open question — resolve before building

- **Does Citadel / NIOSSH accept a Secure Enclave key as an auth method?**
  `SecureEnclave.P256.Signing.PrivateKey` is a different type from
  `P256.Signing.PrivateKey`, so check whether Citadel's
  `SSHClient.connect(authenticationMethod:)` accepts it directly, whether
  swift-nio-ssh's private-key protocol has a conformance for it, or whether
  a custom signer wrapper is needed. If no supported path exists, the fallback
  is a Keychain-stored (non-enclave) P256 key — do not ship a fake enclave key.

### Acceptance

- Key generates with a Face ID prompt; the private key is not exportable
  (verify by attempting export — it must fail).
- The exported public key authenticates against a real server (`ssh -i`
  equivalent: add it to `authorized_keys`, connect).
- Removing / re-enrolling biometrics invalidates the key and the UI says so
  instead of failing silently at connect time.
- Existing Ed25519 and imported keys keep working unchanged.

## 4. Full mosh — stays in Phase 5

No change. Mosh needs a UDP/SSP client port, which is a separate project from
the reconnect work above. Revisit only if auto-reconnect + tmux proves
insufficient for the quick-check use case.

## Testing notes

- Unit-test the reconnect state machine and backoff with plain values (no
  live server): drop → retry schedule → give up → manual reconnect.
- Unit-test `tmux new -A -s pockterm` command construction and the
  per-host/group/global resolution.
- Manual test matrix: Wi-Fi → cellular handover, Airplane Mode toggle,
  background/foreground, server reboot, host without tmux, user disconnect.
- Secure Enclave work needs a real device — the simulator has no enclave.
