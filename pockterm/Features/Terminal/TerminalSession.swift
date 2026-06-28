import SwiftUI
import SwiftTerm

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
    let engine = SSHEngine()
    let terminalView: TerminalView

    var title: String
    var status: Status = .connecting
    var ctrlActive = false

    private let proxy = TerminalDelegateProxy()

    init(host: Host, secretStore: SecretStore) {
        self.host = host
        self.secretStore = secretStore
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
        Task { await engine.send(transformCtrl(bytes)) }
    }

    func sendKeys(_ bytes: [UInt8]) {
        Task { await engine.send(bytes) }
    }

    func run(_ snippet: Snippet) {
        sendKeys(Array((snippet.command + "\n").utf8))
    }

    /// Latches the ctrl key: maps the next alphabetic byte to its control code.
    private func transformCtrl(_ bytes: [UInt8]) -> [UInt8] {
        guard ctrlActive, let first = bytes.first else { return bytes }
        ctrlActive = false
        let upper = first & ~0x20
        guard (0x41...0x5F).contains(upper) else { return bytes }
        return [upper & 0x1F] + bytes.dropFirst()
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
            try await engine.connect(creds)
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
