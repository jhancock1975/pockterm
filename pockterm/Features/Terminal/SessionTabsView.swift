import SwiftUI
import SwiftData
import SwiftTerm

/// Hosts an existing `TerminalView` (owned by a session) inside SwiftUI.
/// Keyboard avoidance is done in UIKit via `keyboardLayoutGuide`, which stays
/// correct across rotations where SwiftUI's automatic avoidance leaves the
/// terminal's bottom rows behind the accessory bar.
///
/// A view lives in one window at a time, and the same terminal moves between
/// the phone and the glasses. So every update makes sure this container holds
/// exactly the terminal it was given. That covers plugging in, unplugging and
/// switching sessions, without either side knowing about the other.
struct TerminalHostView: UIViewRepresentable {
    let terminalView: TerminalView
    /// Off on the glasses, where there's no keyboard to make room for.
    var avoidsKeyboard = true

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        adopt(into: container)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        if terminalView.superview !== uiView { adopt(into: uiView) }
        // Subviews SwiftTerm adds after makeUIView (its own scroller and
        // accessory views) would otherwise inherit the mirrored default.
        uiView.pinLeftToRightForTerminalContent()
    }

    private func adopt(into container: UIView) {
        for case let stale as TerminalView in container.subviews where stale !== terminalView {
            stale.removeFromSuperview()
        }
        terminalView.removeFromSuperview()
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminalView)
        let bottom = avoidsKeyboard ? container.keyboardLayoutGuide.topAnchor : container.bottomAnchor
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: container.topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: bottom),
        ])
        // In Hebrew and Arabic the rest of the app mirrors, but the terminal
        // must not: the server addresses columns from the left. See
        // Localization/LeftToRight.swift. This also keeps the leading/trailing
        // constraints above resolving to left/right.
        container.pinLeftToRightForTerminalContent()
    }
}

/// The full multi-session terminal surface: a tab strip over the active
/// session's terminal, accessory key bar, snippet runner, and host-key notice.
struct SessionTabsView: View {
    @Bindable var manager: SessionManager
    @Query(sort: \Snippet.label) private var snippets: [Snippet]
    @Query(sort: \Host.label) private var hosts: [Host]
    @State private var showingHostPicker = false
    @State private var assistantSession: TerminalSession?
    @State private var themingSession: TerminalSession?
    @State private var filesSession: TerminalSession?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if let session = manager.active {
                    if manager.isGlassesMode {
                        Color.black   // replaced by GlassesPhoneContent in Task 6
                    } else {
                        sessionContent(session)
                    }
                } else {
                    Spacer()
                }
            }
        }
        // Keyboard avoidance is handled in UIKit by TerminalHostView.
        .ignoresSafeArea(.keyboard)
        .alert("Verify Host Key", isPresented: hostKeyPresented,
               presenting: manager.active?.pendingHostKey) { pending in
            Button(pending.storedFingerprint == nil ? "Accept" : "Accept Changed Key",
                   role: pending.storedFingerprint == nil ? nil : .destructive) {
                pending.resume(true)
                manager.active?.pendingHostKey = nil
            }
            Button("Reject", role: .cancel) {
                pending.resume(false)
                manager.active?.pendingHostKey = nil
            }
        } message: { pending in
            Text(hostKeyMessage(pending))
        }
        .sheet(isPresented: $showingHostPicker) {
            NewSessionPicker(hosts: hosts) { host in
                manager.open(host)
                showingHostPicker = false
            }
        }
        .sheet(item: $assistantSession) { session in
            AssistantView(model: session.assistant, host: session.host,
                          secretStore: manager.secretStore)
        }
        .sheet(item: $themingSession) { session in
            ThemePickerSheet(session: session)
        }
        .sheet(item: $filesSession) { session in
            FilesBrowserView(host: session.host, secretStore: session.secretStore,
                             modelContext: session.modelContext)
        }
    }

    /// Compact header: the active session's chip centered (carrying its own
    /// close button), the AI assistant on the leading edge, and new-session,
    /// snippets, files, theme and minimise trailing. A slim tab chip row
    /// appears only when more than one session is open.
    private var topBar: some View {
        VStack(spacing: 6) {
            ZStack {
                if let active = manager.active {
                    activeSessionChip(active)
                } else {
                    Text("Terminal").font(.headline).foregroundStyle(.white)
                }

                HStack(spacing: 12) {
                    // AI sits on the leading edge, opposite the chip's close
                    // button. Trailing, it landed hard against that red ✕ —
                    // a frequently-tapped control touching a destructive one.
                    if let session = manager.active {
                        Button {
                            // Drop the terminal's keyboard first: a sheet
                            // presented under an already-visible keyboard gets
                            // no keyboard notification, so its input bar would
                            // lay out (covered) behind it.
                            session.terminalView.resignFirstResponder()
                            assistantSession = session
                        } label: {
                            Image(systemName: "sparkles")
                        }
                        .accessibilityLabel("AI Assistant")
                    }
                    Spacer()
                    Button { showingHostPicker = true } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Session")
                    if !snippets.isEmpty, let session = manager.active {
                        Menu {
                            ForEach(snippets) { snippet in
                                Button(snippet.label) { session.run(snippet) }
                            }
                        } label: {
                            Image(systemName: "text.badge.plus")
                        }
                        .disabled(session.status != .connected)
                    }
                    if let session = manager.active {
                        Button { filesSession = session } label: {
                            Image(systemName: "folder")
                        }
                        .accessibilityLabel("Browse Files")
                    }
                    if let session = manager.active {
                        Button { themingSession = session } label: {
                            ThemeWheelIcon()
                        }
                        .accessibilityLabel("Terminal Theme")
                        .disabled(session.status != .connected)
                    }
                    Button { manager.minimize() } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Minimize")
                }
            }

            if manager.sessions.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(manager.sessions) { session in
                            tabChip(session)
                        }
                    }
                }
            }
        }
        .tint(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black)
    }

    /// The active session as a bordered pill: name plus the red close button
    /// right beside it.
    private func activeSessionChip(_ session: TerminalSession) -> some View {
        let border = Color(red: 0.3, green: 0.85, blue: 1.0)
        return HStack(spacing: 8) {
            Text(session.title)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.tail)
            closeButton(session, size: .body)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Capsule().fill(.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(border.opacity(0.8), lineWidth: 1.5))
        .frame(maxWidth: 220)
    }

    /// A plain red dot, in the theme wheel's red. The label is spelled out
    /// because a bare circle leaves VoiceOver nothing to describe — the ✕ it
    /// replaced carried its own "Close" description.
    private func closeButton(_ session: TerminalSession, size: Font) -> some View {
        Button { manager.close(session) } label: {
            Image(systemName: "circle.fill")
                .font(size)
                .foregroundStyle(ThemeWheelIcon.red)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close Session")
    }

    private func tabChip(_ session: TerminalSession) -> some View {
        let isActive = session.id == manager.activeID
        return HStack(spacing: 6) {
            closeButton(session, size: .footnote)
            Text(session.title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: 160)
        .background(isActive ? Color.gray.opacity(0.45) : Color.gray.opacity(0.18), in: Capsule())
        .contentShape(Capsule())
        .onTapGesture { manager.activeID = session.id }
    }

    @ViewBuilder
    private func sessionContent(_ session: TerminalSession) -> some View {
        ZStack {
            TerminalHostView(terminalView: session.terminalView)
            SessionStatusView(session: session, manager: manager)
            if session.status == .connected {
                ZoomControlsView(session: session)
                    .id(session.id)
            }
        }
    }

    private var hostKeyPresented: Binding<Bool> {
        Binding(get: { manager.active?.pendingHostKey != nil },
                set: { presented in
                    // Dismissed without a choice counts as rejection.
                    if !presented, let pending = manager.active?.pendingHostKey {
                        pending.resume(false)
                        manager.active?.pendingHostKey = nil
                    }
                })
    }

    private func hostKeyMessage(_ pending: PendingHostKey) -> String {
        var lines: [String] = []
        if let stored = pending.storedFingerprint {
            lines.append("⚠️ This key is DIFFERENT from the one you previously trusted:")
            lines.append("was \(stored)")
            lines.append("Only accept if you expected this change.")
            lines.append("")
        }
        lines.append("\(pending.info.address):\(pending.info.port)  (\(pending.info.keyType))")
        lines.append(pending.info.fingerprint ?? "Fingerprint unavailable for this key type")
        return lines.joined(separator: "\n")
    }

}

/// The theme picker's icon: one circle cut into three equal wedges, red then
/// green then blue. The colours are muted so the button sits quieter than the
/// white symbols beside it, but stay light enough to read on the black bar.
private struct ThemeWheelIcon: View {
    /// A disabled Button dims a text/symbol label by restyling its foreground,
    /// which leaves these explicit fills untouched — so dim them by hand.
    @Environment(\.isEnabled) private var isEnabled

    /// Matches the optical size of the toolbar's SF Symbols.
    private let diameter: CGFloat = 17

    // Spelled out because SwiftTerm exports a `Color` of its own.
    /// Shared with the session close buttons, which are dots in this same red.
    static let red = SwiftUI.Color(red: 0.70, green: 0.24, blue: 0.24)

    private static let wedges: [SwiftUI.Color] = [
        red,
        Color(red: 0.22, green: 0.55, blue: 0.31),
        Color(red: 0.24, green: 0.40, blue: 0.76),
    ]

    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for (index, color) in Self.wedges.enumerated() {
                let start = Angle.degrees(Double(index) * 120 - 90)
                var wedge = Path()
                wedge.move(to: center)
                wedge.addArc(center: center, radius: radius,
                             startAngle: start, endAngle: start + .degrees(120),
                             clockwise: false)
                wedge.closeSubpath()
                context.fill(wedge, with: .color(color))
                // Stroking in the bar's own colour cuts a visible gap along the
                // two radii; the outer arc's share of the stroke is invisible
                // against the same black.
                context.stroke(wedge, with: .color(.black), lineWidth: 1)
            }
        }
        .frame(width: diameter, height: diameter)
        .opacity(isEnabled ? 1 : 0.35)
    }
}

/// Picks a host to open as an additional session without closing existing ones.
private struct NewSessionPicker: View {
    let hosts: [Host]
    let onSelect: (Host) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if hosts.isEmpty {
                    ContentUnavailableView("No Hosts", systemImage: "server.rack",
                                           description: Text("Add a host on the Hosts tab first."))
                } else {
                    List(hosts) { host in
                        Button {
                            onSelect(host)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(host.label).font(.headline)
                                Text("\(host.identity?.username ?? "—")@\(host.address)")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("New Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
