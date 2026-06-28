import SwiftUI
import SwiftData
import SwiftTerm

/// A host key awaiting the user's accept/reject decision.
struct PendingHostKey: Identifiable {
    let id = UUID()
    let info: PresentedHostKey
    /// Non-nil means the presented key differs from a previously trusted one.
    let storedFingerprint: String?
    let resume: (Bool) -> Void
}

/// One live SSH session: owns its engine and a persistent `TerminalView` so it
/// keeps running (and retains scrollback) while another tab is on screen.
@MainActor
@Observable
final class TerminalSession: Identifiable {
    enum Status: Equatable {
        case connecting
        case connected
        case failed(String)
        case closed
    }

    let id = UUID()
    let host: Host
    let secretStore: SecretStore
    let modelContext: ModelContext
    let engine = SSHEngine()
    let terminalView: TerminalView

    var title: String
    var status: Status = .connecting
    var pendingHostKey: PendingHostKey?

    private let proxy = TerminalDelegateProxy()

    init(host: Host, secretStore: SecretStore, modelContext: ModelContext) {
        self.host = host
        self.secretStore = secretStore
        self.modelContext = modelContext
        self.title = host.label
        self.terminalView = TerminalView()
        terminalView.backgroundColor = .black
        terminalView.terminalDelegate = proxy
        proxy.onInput = { [weak self] bytes in self?.handleInput(bytes) }
        proxy.onSize = { [weak self] cols, rows in
            Task { await self?.engine.resize(cols: cols, rows: rows) }
        }
    }

    func handleInput(_ bytes: [UInt8]) {
        Task { await engine.send(bytes) }
    }

    func sendKeys(_ bytes: [UInt8]) {
        Task { await engine.send(bytes) }
    }

    func run(_ snippet: Snippet) {
        sendKeys(Array((snippet.command + "\n").utf8))
    }

    func start() async {
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
            try await engine.connect(creds) { [weak self] presented in
                await self?.decideHostKey(presented) ?? false
            }
            try await engine.openShell(
                cols: 80, rows: 24,
                onOutput: { [weak self] bytes in
                    Task { @MainActor in self?.terminalView.feed(byteArray: ArraySlice(bytes)) }
                },
                onClose: { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        if self.status == .connected { self.status = .closed }
                    }
                })
            status = .connected
            if let startup = host.startupSnippet, !startup.isEmpty {
                sendKeys(Array((startup + "\n").utf8))
            }
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    /// Trust-on-first-use decision for a presented host key. Matches against
    /// stored `KnownHostRecord`s; new or changed keys prompt the user, and an
    /// accepted key is persisted.
    func decideHostKey(_ info: PresentedHostKey) async -> Bool {
        let records = (try? modelContext.fetch(FetchDescriptor<KnownHostRecord>())) ?? []
        let store = KnownHostsStore()

        guard let fingerprint = info.fingerprint else {
            // Couldn't derive a fingerprint; ask the user without persisting.
            return await prompt(info: info, storedFingerprint: nil)
        }

        switch store.evaluate(address: info.address, port: info.port, keyType: info.keyType,
                              presentedFingerprint: fingerprint, against: records) {
        case .matches:
            return true
        case .trustedNew:
            let accepted = await prompt(info: info, storedFingerprint: nil)
            if accepted {
                modelContext.insert(KnownHostRecord(hostAddress: info.address, port: info.port,
                                                    keyType: info.keyType, fingerprintSHA256: fingerprint))
                try? modelContext.save()
            }
            return accepted
        case .mismatch(let stored, let presented):
            let accepted = await prompt(info: info, storedFingerprint: stored)
            if accepted {
                if let record = records.first(where: {
                    $0.hostAddress == info.address && $0.port == info.port && $0.keyType == info.keyType
                }) {
                    record.fingerprintSHA256 = presented
                    try? modelContext.save()
                }
            }
            return accepted
        }
    }

    private func prompt(info: PresentedHostKey, storedFingerprint: String?) async -> Bool {
        await withCheckedContinuation { continuation in
            pendingHostKey = PendingHostKey(info: info, storedFingerprint: storedFingerprint) { decision in
                continuation.resume(returning: decision)
            }
        }
    }

    func disconnect() async {
        await engine.disconnect()
    }
}

/// NSObject delegate bridge so the `@MainActor` session can receive SwiftTerm
/// callbacks through plain closures.
final class TerminalDelegateProxy: NSObject, TerminalViewDelegate {
    var onInput: (([UInt8]) -> Void)?
    var onSize: ((Int, Int) -> Void)?

    func send(source: TerminalView, data: ArraySlice<UInt8>) { onInput?(Array(data)) }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { onSize?(newCols, newRows) }
    func scrolled(source: TerminalView, position: Double) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}
