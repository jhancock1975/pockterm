# Mosh in pockterm — design

**Status:** draft for review, 2026-11-27. The first layer (wire format) is in.

## Why

SSH dies when the phone changes networks or sleeps. Auto-reconnect (1.12)
papers over it by logging in again, but you see the drop and lose anything
not in tmux. Mosh keeps the session alive across Wi-Fi ↔ cellular, sleep and
roaming, because it runs over UDP and the server holds the screen state.

## Constraints

- **Clean room.** Mosh is GPLv3; pockterm is Apache-2.0 on the App Store. We
  write a Swift client of the *protocol* and never copy or port mosh's C++.
- **No new dependency.** Everything is Foundation, CommonCrypto,
  Network.framework and Compression.
- **Server side is the stock `mosh-server`** (1.3/1.4). Users install it the
  usual way; we don't ship anything to the server.

## How a session works

1. **Bootstrap over SSH.** Using the host's existing identity, exec
   `mosh-server new -s -c 256 -l LANG=en_US.UTF-8 -- <shell>` (plus `-p` if the
   host sets a port range). Parse `MOSH CONNECT <port> <22-char key>` from its
   output, then close the SSH connection. If `mosh-server` isn't found, say so
   and offer plain SSH.
2. **UDP to `<host>:<port>`** with Network.framework (`NWConnection`, UDP).
   When the path changes (Wi-Fi → cellular), make a new connection to the same
   port: the server follows the newest authenticated source address, which is
   the whole point of mosh.
3. **State sync (SSP).** Two streams, each a numbered sequence of states:
   - client → server: user input (keystrokes, window size);
   - server → client: the screen.

   Every datagram carries an `Instruction`: "diff takes you from state
   `old_num` to `new_num`", plus `ack_num` (newest peer state we hold) and
   `throwaway_num` (oldest state we still need the peer to diff from).
4. **Screen.** Server diffs are terminal escape sequences meant to be applied
   to the client's copy of the screen *as of `old_num`*. We feed them straight
   into the existing SwiftTerm view, so we keep exactly one screen: a diff is
   applied only when its `old_num` is the state we're showing, otherwise it's
   dropped. The server falls back to diffing from our last ack when its
   optimistic guess goes unacknowledged, so a dropped diff costs one round
   trip, not correctness. (The real mosh client keeps several old screens so
   it can use more diffs; we can add that if loss recovery feels slow.)
5. **Timing.** Send on input immediately (with mosh's short coalescing delay),
   heartbeat every 3 s when idle, retransmit unacked input on an RTT-based
   timer (SRTT/RTTVAR from the timestamp echo, as in TCP). Show "last contact
   N s ago" in the session bar after ~5 s of silence, as mosh does.

## Layers and files (`pockterm/Mosh/`)

| Layer | File | State |
|---|---|---|
| AES-128-OCB (RFC 7253) on CommonCrypto | `AESOCB.swift` | **done**, RFC vectors pass |
| Packets, fragments, zlib, protobuf messages | `MoshWire.swift` | **done**, round-trip tests |
| SSP transport: state numbers, acks, timers, RTT | `MoshTransport.swift` | next |
| UDP + roaming over Network.framework | `MoshConnection.swift` | next |
| `mosh-server new` bootstrap over SSH | `MoshBootstrap.swift` | next |
| Session plumbing: a mosh session behind the same interface `TerminalSession` uses for SSH | changes in `Features/Terminal` | after |
| UI: per-host "Use Mosh" toggle, port range, "last contact" banner | host editor, session bar | after |

## What's deliberately left out of v1

- **Typing prediction** (local echo). Big, fiddly, and only matters on slow
  links. Later.
- **SFTP, port forwarding and the AI assistant's `run_command`** keep using
  SSH. A mosh host opens an SSH connection for those on demand.
- **Scrollback.** Mosh only syncs the visible screen, so there is no
  scrollback in a mosh session (same as the real client). Use tmux.

## Testing

- Unit tests for every layer, with known-answer vectors where a spec has them
  (RFC 7253 for OCB, real zlib output).
- **Interop against a real `mosh-server` on the Mac** (`brew install mosh`,
  test-only, nothing in the app): a headless test drives the transport over
  UDP to `localhost`, types `echo`, and compares the screen with what the
  server holds. Then the simulator verify harness for the UI, and a roaming
  test by killing and recreating the UDP socket mid-session.

## Open questions for John

1. Per-host toggle ("Use Mosh") vs. a global default — I'd do per-host,
   off by default.
2. Is `brew install mosh` on this Mac OK for the interop tests? Without it we
   can only test against our own encoder.
