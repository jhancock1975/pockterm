# Phase 4: Port Forwarding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Local, remote, and dynamic (SOCKS5) SSH tunnels with live status — configure, start/stop, and see which are running.

**Architecture:** A `PortForward` SwiftData model describes each tunnel. A `PortForwardService` actor owns one SSH connection and the tunnel. For **local** and **dynamic** forwards it runs a NIO `ServerBootstrap` listener on the device; each accepted connection is glued (bidirectional `ByteBuffer` relay) to a Citadel `createDirectTCPIPChannel` to the target. **Dynamic** adds a minimal SOCKS5 front-end (handshake + CONNECT) that picks the target per connection. **Remote** uses Citadel's `startListening`/`withRemotePortForward`. Pure logic (model, SOCKS5 request parsing) is TDD'd; tunneling is integration-verified against localhost sshd.

**Tech Stack:** Citadel direct-TCP/remote-forward, SwiftNIO (`ServerBootstrap`, `MultiThreadedEventLoopGroup.singleton`), SwiftUI, SwiftData. No new packages.

## Global Constraints

- Same as prior phases: iOS 26.5+, Swift 5 mode, secrets only via `SecretStore`, reuse `HostConnection.credentials` + host-key prompt.
- New app files auto-compile; new TEST files need `ruby scripts/setup_project.rb`.
- **Agent forwarding** is out of scope this phase (Citadel has no clear public API); note it as deferred.

---

### Task 1: PortForward model

**Files:**
- Create: `pockterm/Model/PortForward.swift`
- Modify: `pockterm/App/AppContainer.swift` (register model) + every test `ModelContainer(for:)`
- Test: `pocktermTests/PortForwardModelTests.swift`

**Interfaces:**
- Produces:
  - `enum ForwardType: String, Codable { case local, remote, dynamic }`
  - `@Model final class PortForward { var id: UUID; var label: String; var typeRaw: String; var bindPort: Int; var remoteHost: String; var remotePort: Int; var host: Host?; var type: ForwardType {get/set} }`
  - For `dynamic`, `remoteHost`/`remotePort` are ignored (target is per-SOCKS-request).

- [ ] **Step 1: Failing test** — persist a local forward with a host relationship; read back `type`, `bindPort`, `remoteHost`, `remotePort`.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** model + register in `AppContainer` and tests.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `"Add PortForward model"`.

---

### Task 2: SOCKS5 CONNECT request parser (pure logic, TDD)

**Files:**
- Create: `pockterm/Forwarding/SOCKS5.swift`
- Test: `pocktermTests/SOCKS5Tests.swift`

**Interfaces:**
- Produces:
  - `enum SOCKS5 { case needMore; case greeting(methods: Int); ... }` — minimal helpers:
  - `static func parseGreeting(_ bytes: [UInt8]) -> Bool?` (true if no-auth offered; nil if incomplete)
  - `static func parseConnect(_ bytes: [UInt8]) -> SOCKSTarget?` returning `struct SOCKSTarget { let host: String; let port: Int }` for CMD=CONNECT with IPv4/domain/IPv6 address types; nil if incomplete/unsupported.
  - `static let greetingReply: [UInt8]` = `[0x05, 0x00]`
  - `static func connectReply(success: Bool) -> [UInt8]` (VER, REP, RSV, ATYP IPv4, 0.0.0.0:0).

- [ ] **Step 1: Failing test** — greeting `[5,1,0]` → no-auth true; CONNECT to IPv4 `1.2.3.4:80` parses host "1.2.3.4" port 80; CONNECT to domain "example.com:443" parses; truncated input → nil.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** the parser.
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** `"Add SOCKS5 CONNECT request parser"`.

---

### Task 3: PortForwardService (NIO listener + Citadel channels)

**Files:**
- Create: `pockterm/Forwarding/GlueHandler.swift`
- Create: `pockterm/Forwarding/PortForwardService.swift`
- Test: `pocktermTests/PortForwardServiceTests.swift` (integration; skips without localhost sshd)

**Interfaces:**
- Produces:
  - `final class GlueHandler: ChannelDuplexHandler` — bidirectional `ByteBuffer` relay between a local channel and its partner SSH channel; closes the partner on EOF/error.
  - `actor PortForwardService` with:
    - `func connect(_ creds: SSHCredentials, onHostKey: …) async throws`
    - `func startLocal(bindHost: String, bindPort: Int, targetHost: String, targetPort: Int) async throws -> Int` (returns the actually-bound port; 0 binds ephemeral)
    - `func startDynamic(bindHost: String, bindPort: Int) async throws -> Int` (SOCKS5)
    - `func startRemote(bindPort: Int, targetHost: String, targetPort: Int) async throws`
    - `func stop() async`
- Consumes: `SSHClient.createDirectTCPIPChannel(using: SSHChannelType.DirectTCPIP(targetHost:targetPort:originatorAddress:), initialize:)`, `ServerBootstrap(group: .singleton)`, Citadel remote-forward APIs.

**Local-forward flow:** `ServerBootstrap` binds `bindHost:bindPort`; childChannelInitializer pauses autoRead, opens a direct-TCPIP channel to the target, then installs a `GlueHandler` pair (local↔ssh) and resumes reads. **Dynamic-forward flow:** the child first runs a `SOCKS5Handler` that buffers the greeting/CONNECT, replies, then opens the direct-TCPIP channel to the parsed target and swaps in the glue. Integration test (`startLocal` → bind ephemeral → target `127.0.0.1:22` → connect a raw socket to the bound port → expect the `SSH-2.0` banner) proves end-to-end.

- [ ] **Step 1: Implement** `GlueHandler`.
- [ ] **Step 2: Implement** `PortForwardService.connect` + `startLocal` + `stop`.
- [ ] **Step 3: Integration test** local forward to `127.0.0.1:22`, assert banner begins `SSH-2.0`. Run on simulator (skips if no sshd).
- [ ] **Step 4: Implement** dynamic (SOCKS5) and remote forwarding.
- [ ] **Step 5: Build** for simulator; verify compiles.
- [ ] **Step 6: Commit** `"Add PortForwardService: local, dynamic, and remote tunnels"`.

---

### Task 4: Port Forwarding UI

**Files:**
- Create: `pockterm/Features/Forwarding/ForwardsListView.swift`
- Create: `pockterm/Features/Forwarding/ForwardEditorView.swift`
- Create: `pockterm/Features/Forwarding/ForwardRunner.swift` (@MainActor @Observable; owns a `PortForwardService` + status per active forward)
- Modify: `pockterm/App/RootTabView.swift` (replace Port Forwarding placeholder)

**Interfaces:**
- Produces: a Port Forwarding tab listing configured `PortForward`s with a start/stop toggle and live status (stopped / connecting / active(boundPort) / failed). Editor: label, type picker, bind port, remote host/port (hidden for dynamic), and host picker. `ForwardRunner` resolves creds via `HostConnection.credentials`, runs the host-key prompt, starts the chosen tunnel, and surfaces status.
- Consumes: `PortForward` (Task 1), `PortForwardService` (Task 3), host-key prompt pattern.

- [ ] **Step 1:** `ForwardsListView` + `ForwardEditorView` (CRUD).
- [ ] **Step 2:** `ForwardRunner` wiring start/stop + status + host-key alert.
- [ ] **Step 3:** Replace the Port Forwarding placeholder tab.
- [ ] **Step 4:** Build for simulator; run unit tests; build/install/launch on device `<DEVICE_UDID>`.
- [ ] **Step 5: Commit** `"Add port forwarding UI"`.

---

## Self-Review notes

- **Spec coverage (Phase 4):** local/remote/dynamic tunnels (Tasks 2,3) ✓; live status UI (Task 4) ✓.
- **Deferred:** agent forwarding (no clear Citadel API) — tracked as a known gap.
- **iOS reality:** a device-local SOCKS/forward is usable by the app itself and by other apps configured to use it; iOS won't route arbitrary system traffic through it. The tunnels and status are real and verifiable regardless.
