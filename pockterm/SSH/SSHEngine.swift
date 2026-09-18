import Foundation
import Citadel
import Crypto
import NIOCore
import NIOSSH

enum SSHEngineError: Error, LocalizedError {
    case notConnected
    case invalidKey
    var errorDescription: String? {
        switch self {
        case .notConnected: return String(localized: "Not connected")
        case .invalidKey: return String(localized: "Invalid private key")
        }
    }
}

/// Owns the lifecycle of a single SSH connection and its interactive PTY shell.
///
/// Citadel exposes the shell through a closure-based `withPTY(_:perform:)` that
/// keeps the channel open for the duration of the closure. To allow the rest of
/// the app to push keystrokes and resize events into that closure, the engine
/// funnels them through an `AsyncStream` whose continuation lives on the actor
/// while the `TTYStdinWriter` itself stays local to the closure.
actor SSHEngine {
    private enum Input {
        case bytes([UInt8])
        case resize(cols: Int, rows: Int)
    }

    private var client: SSHClient?
    private var shellTask: Task<Void, Never>?
    private var inputContinuation: AsyncStream<Input>.Continuation?

    var isConnected: Bool { client?.isConnected ?? false }

    func connect(_ creds: SSHCredentials,
                 onHostKey: @escaping @Sendable (PresentedHostKey) async -> Bool) async throws {
        let method = try creds.authenticationMethod()
        let validator = CallbackHostKeyValidator(address: creds.host, port: creds.port, decide: onHostKey)
        client = try await SSHClient.connect(
            host: creds.host,
            port: creds.port,
            authenticationMethod: method,
            hostKeyValidator: .custom(validator),
            reconnect: .never,
            algorithms: .pockterm
        )
    }

    /// Opens an interactive shell. `onOutput` is called with raw terminal bytes
    /// as they arrive; `onClose` fires when the remote shell ends.
    func openShell(cols: Int, rows: Int,
                   onOutput: @escaping @Sendable ([UInt8]) -> Void,
                   onClose: @escaping @Sendable () -> Void) async throws {
        guard let client else { throw SSHEngineError.notConnected }

        let (inputStream, continuation) = AsyncStream<Input>.makeStream()
        inputContinuation = continuation

        let request = SSHChannelRequestEvent.PseudoTerminalRequest(
            wantReply: true,
            term: "xterm-256color",
            terminalCharacterWidth: cols,
            terminalRowHeight: rows,
            terminalPixelWidth: 0,
            terminalPixelHeight: 0,
            terminalModes: .init([:]))

        // Same upstream gap as PortForwardService: Citadel's SSHClient is not
        // Sendable, though SSHClientSession beside it is. Scoped to the capture
        // so the assumption is visible rather than asserted for the type.
        nonisolated(unsafe) let unsafeClient = client
        shellTask = Task {
            do {
                try await unsafeClient.withPTY(request) { inbound, outbound in
                    // inbound/outbound are Citadel's PTY halves and are not
                    // Sendable, but the two task-group children below use one
                    // each and never the same one — reads on inbound, writes on
                    // outbound. The split is by construction, not by the type
                    // system, which is why these are scoped opt-outs.
                    // Each half goes to exactly one child task — reads on
                    // inbound, writes on outbound — but they stay reachable
                    // from this scope, which is what the compiler objects to.
                    // Boxing hands each child its own reference and keeps the
                    // unchecked claim to this one narrow use.
                    let inboundBox = UncheckedBox(inbound)
                    let outboundBox = UncheckedBox(outbound)
                    try await withThrowingTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for try await chunk in inboundBox.value {
                                switch chunk {
                                case .stdout(let buffer), .stderr(let buffer):
                                    onOutput(Array(buffer.readableBytesView))
                                }
                            }
                        }
                        group.addTask {
                            for await input in inputStream {
                                switch input {
                                case .bytes(let bytes):
                                    try await outboundBox.value.write(ByteBuffer(bytes: bytes))
                                case .resize(let c, let r):
                                    try await outboundBox.value.changeSize(cols: c, rows: r, pixelWidth: 0, pixelHeight: 0)
                                }
                            }
                        }
                        // When either side finishes (remote EOF or local stop), tear down both.
                        try await group.next()
                        group.cancelAll()
                    }
                }
            } catch {
                // Connection or shell error: fall through to close notification.
            }
            onClose()
        }
    }

    /// Runs one command on a fresh exec channel of the live connection and
    /// returns its merged stdout+stderr. The interactive PTY is not disturbed.
    /// This Citadel release routes stderr into a thrown TTYSTDError instead of
    /// merging streams, so merge in a remote subshell — the agent wants the
    /// combined text either way.
    ///
    /// A non-zero exit is **not** an error here. `executeCommand` throws
    /// `CommandFailed` on any non-zero status and discards everything the
    /// command printed, which turns `grep` finding no match — exit 1, and
    /// completely normal — into an opaque Citadel error with no output. A
    /// shell tool has to report the output and the status, so this streams the
    /// chunks itself, keeps what arrived, and appends the status.
    ///
    /// Oversized output is truncated for the same reason: `maxResponseSize`
    /// throws `commandOutputTooLarge` mid-stream and drops the whole response,
    /// so a command that prints a lot returns nothing at all.
    func exec(_ command: String, maxOutputBytes: Int = 64 * 1024) async throws -> String {
        guard let client else { throw SSHEngineError.notConnected }

        var out = [UInt8]()
        var truncated = false
        var exitCode: Int?

        func append(_ buffer: ByteBuffer) {
            guard out.count < maxOutputBytes else { truncated = true; return }
            let room = maxOutputBytes - out.count
            let bytes = buffer.readableBytesView
            out.append(contentsOf: bytes.prefix(room))
            if bytes.count > room { truncated = true }
        }

        do {
            nonisolated(unsafe) let unsafeClient = client
            for try await chunk in try await unsafeClient.executeCommandStream("( \(command) ) 2>&1") {
                switch chunk {
                case .stdout(let buffer), .stderr(let buffer): append(buffer)
                }
            }
        } catch let failure as SSHClient.CommandFailed {
            exitCode = failure.exitCode
        }

        var text = String(decoding: out, as: UTF8.self)
        if truncated {
            text += "\n[output truncated at \(maxOutputBytes) bytes]"
        }
        if let exitCode {
            text += "\n[exit status \(exitCode)]"
        }
        return text
    }

    func send(_ bytes: [UInt8]) {
        inputContinuation?.yield(.bytes(bytes))
    }

    func resize(cols: Int, rows: Int) {
        inputContinuation?.yield(.resize(cols: cols, rows: rows))
    }

    func disconnect() async {
        inputContinuation?.finish()
        shellTask?.cancel()
        if let client {
            nonisolated(unsafe) let unsafeClient = client
            try? await unsafeClient.close()
        }
        client = nil
        inputContinuation = nil
    }
}

/// Carries a non-Sendable value into exactly one child task.
///
/// Citadel's PTY halves are not Sendable and the task group below needs one
/// each. Boxing keeps the unchecked claim at the point of use instead of
/// conforming a third-party type we do not own.
nonisolated struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
