import SwiftUI
import SwiftData
import SwiftTerm

/// Connects to a host and presents the live interactive terminal.
struct TerminalSessionView: View {
    let secretStore: SecretStore
    let host: Host
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Snippet.label) private var snippets: [Snippet]

    @State private var engine = SSHEngine()
    @State private var terminal: TerminalView?
    @State private var status: Status = .connecting
    @State private var ctrlActive = false

    enum Status: Equatable {
        case connecting
        case connected
        case failed(String)
        case closed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    SwiftTermView(
                        onInput: { bytes in
                            let out = transformCtrl(bytes)
                            Task { await engine.send(out) }
                        },
                        onSizeChange: { cols, rows in
                            Task { await engine.resize(cols: cols, rows: rows) }
                        },
                        onReady: { terminal = $0 })
                    TerminalKeyAccessoryBar(
                        send: { bytes in Task { await engine.send(bytes) } },
                        ctrlActive: $ctrlActive)
                }
                if status == .connecting {
                    ProgressView("Connecting…").controlSize(.large).tint(.white)
                }
                if case .failed(let message) = status {
                    ContentUnavailableView("Connection Failed", systemImage: "xmark.octagon",
                                           description: Text(message))
                        .foregroundStyle(.white)
                }
            }
            .navigationTitle(host.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !snippets.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(snippets) { snippet in
                                Button(snippet.label) { run(snippet) }
                            }
                        } label: {
                            Image(systemName: "text.badge.plus")
                        }
                        .disabled(status != .connected)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { Task { await engine.disconnect(); dismiss() } }
                }
            }
            .task { await start() }
            .onDisappear { Task { await engine.disconnect() } }
        }
    }

    /// Sends a snippet's command (with a trailing newline) into the live shell.
    private func run(_ snippet: Snippet) {
        let bytes = Array((snippet.command + "\n").utf8)
        Task { await engine.send(bytes) }
    }

    /// Latches the ctrl key: maps the next alphabetic byte to its control code.
    private func transformCtrl(_ bytes: [UInt8]) -> [UInt8] {
        guard ctrlActive, let first = bytes.first else { return bytes }
        ctrlActive = false
        let upper = first & ~0x20  // normalize to uppercase letter range
        guard (0x41...0x5F).contains(upper) else { return bytes }
        return [upper & 0x1F] + bytes.dropFirst()
    }

    private func start() async {
        let effective = EffectiveHostSettings.resolve(host: host)
        guard let identity = effective.identity else {
            status = .failed("This host has no identity. Edit it and assign one.")
            return
        }
        host.lastConnectedAt = .now
        let auth: SSHAuth
        switch identity.authMethod {
        case .password:
            let password = (try? secretStore.getString(identity.id.uuidString)) ?? ""
            auth = .password(password ?? "")
        case .key:
            guard let keyId = identity.keyRef,
                  let pem = (try? secretStore.getString(keyId.uuidString)) ?? nil,
                  let seed = KeyManager.seed(fromPEM: pem) else {
                status = .failed("The identity's key is missing.")
                return
            }
            auth = .ed25519Seed(seed)
        }

        let creds = SSHCredentials(host: host.address, port: effective.port,
                                   username: identity.username, auth: auth)
        do {
            try await engine.connect(creds)
            try await engine.openShell(
                cols: 80, rows: 24,
                onOutput: { bytes in
                    Task { @MainActor in terminal?.feed(byteArray: ArraySlice(bytes)) }
                },
                onClose: {
                    Task { @MainActor in if status == .connected { status = .closed }; dismiss() }
                })
            status = .connected
        } catch {
            status = .failed(error.localizedDescription)
        }
    }
}
