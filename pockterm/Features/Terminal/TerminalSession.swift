import SwiftUI
import SwiftData
import SwiftTerm

/// One live SSH session: owns its engine and a persistent `TerminalView` so it
/// keeps running (and retains scrollback) while another tab is on screen.
@MainActor
@Observable
final class TerminalSession: Identifiable, HostKeyDeciding {
    enum Status: Equatable {
        case connecting
        case connected
        case failed(String)
        case closed
        case idleDisconnected
    }

    let id = UUID()
    let host: Host
    let secretStore: SecretStore
    let modelContext: ModelContext
    let engine = SSHEngine()
    let terminalView: TerminalView

    /// Session-local font size: seeded from resolved settings, mutated live by
    /// pinch-zoom, and never written back to the model (zoom is session-only).
    var currentFontSize: Int = 14

    /// The un-zoomed size for this session: the resolved size captured at
    /// session start. Reset returns `currentFontSize` to this value. Like
    /// `currentFontSize`, it is session-only and never persisted.
    let baselineFontSize: Int

    /// True while this session's terminal is on the glasses. The text size
    /// then comes from `glassesFontSize` instead of the phone's zoom.
    private(set) var isGlassesMode = false
    private(set) var glassesFontSize = GlassesTextSize.defaultSize

    /// The size the terminal is drawn at right now.
    var displayedFontSize: Int { isGlassesMode ? glassesFontSize : currentFontSize }

    /// Moves this session in or out of glasses mode, or changes the glasses
    /// size. Leaving hands caret focus-tracking back to the terminal itself,
    /// which TerminalKeyboardProxy turns off while it holds the keyboard.
    func setGlassesMode(_ on: Bool, fontSize: Int) {
        guard on != isGlassesMode || fontSize != glassesFontSize else { return }
        isGlassesMode = on
        glassesFontSize = fontSize
        if !on { terminalView.caretViewTracksFocus = true }
        (terminalView.inputAccessoryView as? KeyBarView)?.scrollsLocally = on
        applyAppearance()
    }

    var title: String
    /// Assign through `setStatus` — the caret has to be kept in step with it.
    private(set) var status: Status = .connecting
    var pendingHostKey: PendingHostKey?
    /// Set by SessionManager.open so agent tools can open further sessions.
    weak var sessionManager: SessionManager?

    private let proxy = TerminalDelegateProxy()
    private var lineTracker = TypedLineTracker()
    private var _assistant: AssistantModel?
    private var _files: FilesBrowserModel?
    private var zoomStartSize: Int = 14
    private var lastActivityAt = Date()
    private var lastCols = 80
    private var lastRows = 24
    private var keepAliveTimer: Timer?
    private var holdSeconds = 0
    /// Declines DEC private mode 69 on the way in; see `MarginModeFilter` for
    /// the SwiftTerm defect it works around. Stateful across reads, so it must
    /// live as long as the session.
    private var marginFilter = MarginModeFilter()

    /// This session's AI assistant, created on first use so the transcript
    /// survives closing and reopening the assistant sheet.
    var assistant: AssistantModel {
        if let _assistant { return _assistant }
        let created = AssistantModel(session: self, secretStore: secretStore,
                                     modelContext: modelContext)
        _assistant = created
        return created
    }

    /// This session's file browser for glasses mode, created on first use.
    /// It lives with the session rather than the view: the view comes and goes
    /// with every tab switch and minimise, and taking the SFTP connection down
    /// with it cut off any upload or download in flight.
    var files: FilesBrowserModel {
        if let _files { return _files }
        let created = FilesBrowserModel(host: host, secretStore: secretStore,
                                        modelContext: modelContext)
        _files = created
        return created
    }

    init(host: Host, secretStore: SecretStore, modelContext: ModelContext) {
        self.host = host
        self.secretStore = secretStore
        self.modelContext = modelContext
        self.title = host.label
        self.terminalView = TerminalView()
        let resolvedSize = EffectiveHostSettings.resolve(host: host).fontSize
        self.currentFontSize = resolvedSize
        self.baselineFontSize = resolvedSize
        terminalView.terminalDelegate = proxy
        terminalView.inputAccessoryView = KeyBarView(terminalView: terminalView)
        proxy.onInput = { [weak self] bytes in self?.handleInput(bytes) }
        proxy.onSize = { [weak self] cols, rows in
            guard let self else { return }
            self.lastCols = cols; self.lastRows = rows
            Task { await self.engine.resize(cols: cols, rows: rows) }
        }
        applyAppearance()

        let pinch = UIPinchGestureRecognizer(target: proxy, action: #selector(TerminalDelegateProxy.handlePinch(_:)))
        pinch.delegate = proxy
        proxy.onPinch = { [weak self] recognizer in self?.handlePinch(recognizer) }
        terminalView.addGestureRecognizer(pinch)
    }

    /// The one way session state changes, so the caret can follow it.
    private func setStatus(_ new: Status) {
        guard new != status else { return }
        status = new
        applyCaretLiveness()
    }

    /// Stops the caret blinking once the far end can no longer take a
    /// keystroke, and starts it again if the session comes back.
    ///
    /// A blinking caret is the universal sign of a prompt waiting for input.
    /// Left running over a shell that has exited, a connection that failed, or
    /// an idle disconnect, it invites you to type into nothing and wonder why
    /// the server is ignoring you — which is exactly the confusion this app
    /// exists to avoid. The caret stays on screen, steady, so it still marks
    /// where the output stopped.
    ///
    /// `cursorStyleChanged` restyles the caret view without touching
    /// `options.cursorStyle`, so the emulator keeps its own idea of the shape
    /// and a DECSCUSR the server sent earlier is not lost.
    private func applyCaretLiveness() {
        let terminal = terminalView.getTerminal()
        let requested = terminal.options.cursorStyle
        terminalView.cursorStyleChanged(
            source: terminal,
            newStyle: status.acceptsInput ? requested : requested.steady)
    }

    /// Resolves this host's effective appearance and applies it to the
    /// terminal view (font + full ANSI palette + native fg/bg/cursor).
    func applyAppearance() {
        let s = EffectiveHostSettings.resolve(host: host)
        let theme = TerminalTheme.theme(id: s.themeID)
        let fontID = TerminalFont.font(id: s.fontID).id
        let size = CGFloat(displayedFontSize)
        terminalView.font = UIFont(name: fontID, size: size)
            ?? UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
        if theme.ansi.count == 16 { terminalView.installColors(theme.ansi) }
        terminalView.nativeForegroundColor = TerminalTheme.uiColor(theme.foreground)
        terminalView.nativeBackgroundColor = TerminalTheme.uiColor(theme.background)
        terminalView.backgroundColor = TerminalTheme.uiColor(theme.background)
        terminalView.caretColor = TerminalTheme.uiColor(theme.cursor)
    }

    /// Change this session's theme live and persist it as the host's default.
    /// `id == nil` clears the host override so the theme resolves from the
    /// group/global default again. Applies immediately via the existing
    /// appearance path — no reconnect. Does not touch font or size.
    func setTheme(id: String?) {
        host.themeID = id
        try? modelContext.save()
        applyAppearance()
    }

    func handleInput(_ bytes: [UInt8]) {
        lastActivityAt = .now
        Task { await engine.send(bytes) }
        if let finished = lineTracker.consume(bytes) {
            recordHistory(finished)
        }
    }

    func sendKeys(_ bytes: [UInt8]) {
        Task { await engine.send(bytes) }
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

    func run(_ snippet: Snippet) {
        sendKeys(Array((snippet.command + "\n").utf8))
    }

    func start() async {
        let creds: SSHCredentials
        switch HostConnection.credentials(for: host, secretStore: secretStore) {
        case .failure(let message):
            setStatus(.failed(message))
            return
        case .success(let resolved):
            creds = resolved
        }
        host.lastConnectedAt = .now

        do {
            try await connectCheckingHostKey { [engine] validate in
                try await engine.connect(creds, onHostKey: validate)
            }
            // The terminal's real size, not a guess. This used to open every
            // shell at a hard-coded 80x24: SwiftTerm reports its size through
            // proxy.onSize during layout, which is before the shell exists, so
            // nothing ever corrected it and the server kept formatting for 80
            // columns. Anything full-screen — top, vim, htop — then wrapped
            // every line on a display that is nearer 46 columns, which is the
            // exact garbling this app exists to avoid. The keep-alive tick did
            // eventually send the true size, but minutes later.
            try await engine.openShell(
                cols: lastCols, rows: lastRows,
                onOutput: { [weak self] bytes in
                    Task { @MainActor in
                        guard let self else { return }
                        // Server output counts as activity: a streaming session
                        // (tail -f, top) is in use and must not be idle-disconnected.
                        self.lastActivityAt = .now
                        self.terminalView.feed(byteArray: ArraySlice(self.marginFilter.filter(bytes)))
                    }
                },
                onClose: { [weak self] in
                    Task { @MainActor in
                        guard let self else { return }
                        self.keepAliveTimer?.invalidate(); self.keepAliveTimer = nil
                        if self.status == .connected { self.setStatus(.closed) }
                    }
                })
            setStatus(.connected)
            lastActivityAt = .now
            holdSeconds = EffectiveHostSettings.resolveKeepAlive(
                host: host, globalDefault: ConnectionSettings.single(in: modelContext).defaultKeepAliveSeconds)
            startKeepAliveTimer()
            if let startup = host.startupSnippet, !startup.isEmpty {
                sendKeys(Array((startup + "\n").utf8))
            }
        } catch {
            setStatus(.failed(error.localizedDescription))
        }
    }

    func disconnect() async {
        keepAliveTimer?.invalidate(); keepAliveTimer = nil
        await engine.disconnect()
        await _files?.disconnect()
    }

    private func startKeepAliveTimer() {
        keepAliveTimer?.invalidate()
        guard holdSeconds > 0 else { return }   // Off = today's behavior
        keepAliveTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(KeepAlive.interval),
                                              repeats: true) { [weak self] _ in
            Task { @MainActor in self?.keepAliveTick() }
        }
    }

    private func keepAliveTick() {
        guard status == .connected else { return }
        let idle = Int(Date().timeIntervalSince(lastActivityAt))
        if KeepAlive.shouldIdleDisconnect(idleSeconds: idle, holdSeconds: holdSeconds) {
            keepAliveTimer?.invalidate(); keepAliveTimer = nil
            setStatus(.idleDisconnected)
            Task { await engine.disconnect() }
            return
        }
        // Not yet at the limit: emit real SSH traffic (a window-change at the
        // current size) so the server/NAT does not drop the idle session.
        Task { await engine.resize(cols: lastCols, rows: lastRows) }
    }

    /// Session-only pinch-to-zoom: mutates `currentFontSize` live within the
    /// clamped range and never writes back to `Host` settings.
    private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        switch recognizer.state {
        case .began:
            zoomStartSize = currentFontSize
        case .changed:
            let size = TerminalZoom.clamped(base: zoomStartSize, scale: recognizer.scale)
            if size != currentFontSize {
                currentFontSize = size
                applyAppearance()
            }
        default:
            break
        }
    }

    /// True when the live session size differs from the un-zoomed baseline.
    /// Drives the reset control's visibility.
    var isZoomed: Bool { currentFontSize != baselineFontSize }

    /// Session-only: return the terminal to its baseline size and reflow.
    /// No-op when already at baseline. Never writes back to `Host`.
    func resetZoom() {
        guard currentFontSize != baselineFontSize else { return }
        currentFontSize = baselineFontSize
        applyAppearance()
    }
}

/// NSObject delegate bridge so the `@MainActor` session can receive SwiftTerm
/// callbacks through plain closures.
final class TerminalDelegateProxy: NSObject, TerminalViewDelegate {
    var onInput: (([UInt8]) -> Void)?
    var onSize: ((Int, Int) -> Void)?
    var onPinch: ((UIPinchGestureRecognizer) -> Void)?

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

    @objc func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        onPinch?(recognizer)
    }
}

/// Allows the pinch recognizer to run simultaneously with SwiftTerm's own
/// pan/tap gestures (selection, scroll) instead of suppressing them.
extension TerminalDelegateProxy: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}
