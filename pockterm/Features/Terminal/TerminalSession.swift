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
    /// Commands shown in the ctrl-R-style dropdown (most recent first).
    var suggestionCommands: [String] = []
    var suggestionsVisible = false

    private let proxy = TerminalDelegateProxy()
    private var lineTracker = TypedLineTracker()
    private var idleTask: Task<Void, Never>?

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
        // Typing dismisses the dropdown; it only reappears after the line is
        // empty and idle for 5 seconds.
        suggestionsVisible = false
        if let finished = lineTracker.consume(bytes) {
            recordHistory(finished)
        }
        restartIdleTimer()
    }

    func sendKeys(_ bytes: [UInt8]) {
        Task { await engine.send(bytes) }
    }

    /// Tapping a dropdown row inserts the *next part* of that command (the next
    /// whitespace-delimited token beyond what's already typed) — tap again for
    /// the part after that, and so on. Does not press Enter.
    func applyNextPart(of command: String) {
        guard let part = nextPart(of: command, after: lineTracker.line) else { return }
        let bytes = Array(part.utf8)
        sendKeys(bytes)
        _ = lineTracker.consume(bytes)   // keep the typed-line model in sync
        refreshDropdown()                // stay open, re-filter to the new line
    }

    /// The next token to insert to advance `line` toward `command`.
    private func nextPart(of command: String, after line: String) -> String? {
        guard command.hasPrefix(line), command != line else { return nil }
        let rest = Substring(command.dropFirst(line.count))
        var index = rest.startIndex
        while index < rest.endIndex, rest[index] == " " { index = rest.index(after: index) }
        while index < rest.endIndex, rest[index] != " " { index = rest.index(after: index) }
        return String(rest[rest.startIndex..<index])
    }

    private func recordHistory(_ command: String) {
        let hostID = host.id
        let existing = (try? modelContext.fetch(FetchDescriptor<CommandHistory>(
            predicate: #Predicate { $0.hostID == hostID && $0.command == command }))) ?? []
        if let entry = existing.first {
            entry.count += 1
            entry.lastUsedAt = .now
        } else {
            modelContext.insert(CommandHistory(hostID: hostID, command: command))
        }
        try? modelContext.save()
    }

    /// Restarts the 5-second idle timer. When it fires with an empty line, the
    /// dropdown appears showing the most recent commands (like ctrl-R).
    func restartIdleTimer() {
        idleTask?.cancel()
        idleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled, let self, self.lineTracker.line.isEmpty else { return }
            self.refreshDropdown()
        }
    }

    /// Populates the dropdown with the 3 most recent history commands that match
    /// the current line (most recent first).
    private func refreshDropdown() {
        let line = lineTracker.line
        let hostID = host.id
        let rows = (try? modelContext.fetch(FetchDescriptor<CommandHistory>(
            predicate: #Predicate { $0.hostID == hostID },
            sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]))) ?? []
        var seen = Set<String>()
        var commands: [String] = []
        for row in rows where row.command.hasPrefix(line) && row.command != line {
            if seen.insert(row.command).inserted { commands.append(row.command) }
            if commands.count == 3 { break }
        }
        suggestionCommands = commands
        suggestionsVisible = !commands.isEmpty
    }

    func run(_ snippet: Snippet) {
        sendKeys(Array((snippet.command + "\n").utf8))
    }

    func start() async {
        let creds: SSHCredentials
        switch HostConnection.credentials(for: host, secretStore: secretStore) {
        case .failure(let message):
            status = .failed(message)
            return
        case .success(let resolved):
            creds = resolved
        }
        host.lastConnectedAt = .now

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
            restartIdleTimer()
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
        idleTask?.cancel()
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
