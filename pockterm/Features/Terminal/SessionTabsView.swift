import SwiftUI
import SwiftData
import SwiftTerm

/// Hosts an existing `TerminalView` (owned by a session) inside SwiftUI.
/// Keyboard avoidance is done in UIKit via `keyboardLayoutGuide`, which stays
/// correct across rotations where SwiftUI's automatic avoidance leaves the
/// terminal's bottom rows behind the accessory bar.
struct TerminalHostView: UIViewRepresentable {
    let terminalView: TerminalView

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        terminalView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminalView)
        NSLayoutConstraint.activate([
            terminalView.topAnchor.constraint(equalTo: container.topAnchor),
            terminalView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminalView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            terminalView.bottomAnchor.constraint(equalTo: container.keyboardLayoutGuide.topAnchor),
        ])
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// The full multi-session terminal surface: a tab strip over the active
/// session's terminal, accessory key bar, snippet runner, and host-key notice.
struct SessionTabsView: View {
    @Bindable var manager: SessionManager
    @Query(sort: \Snippet.label) private var snippets: [Snippet]
    @Query(sort: \Host.label) private var hosts: [Host]
    @State private var showingHostPicker = false
    @State private var assistantSession: TerminalSession?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                if let session = manager.active {
                    sessionContent(session)
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
    }

    /// Compact header: the active session's name centered, a red close button
    /// on the leading edge, and the snippet runner + exit trailing. A slim tab
    /// chip row appears only when more than one session is open.
    private var topBar: some View {
        VStack(spacing: 6) {
            ZStack {
                if let active = manager.active {
                    activeSessionChip(active)
                } else {
                    Text("Terminal").font(.headline).foregroundStyle(.white)
                }

                HStack(spacing: 12) {
                    Spacer()
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

    /// The active session as a bordered, softly glowing pill: name plus the red
    /// close button right beside it.
    private func activeSessionChip(_ session: TerminalSession) -> some View {
        let glow = Color(red: 0.3, green: 0.85, blue: 1.0)
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
        .overlay(Capsule().strokeBorder(glow.opacity(0.8), lineWidth: 1.5))
        .shadow(color: glow.opacity(0.55), radius: 8)
        .frame(maxWidth: 220)
    }

    /// Apple-style filled-circle close: white glyph on a red circle.
    private func closeButton(_ session: TerminalSession, size: Font) -> some View {
        Button { manager.close(session) } label: {
            Image(systemName: "xmark.circle.fill")
                .font(size)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .red)
        }
        .buttonStyle(.plain)
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
            switch session.status {
            case .connecting:
                ProgressView("Connecting…").controlSize(.large).tint(.white)
            case .failed(let message):
                ContentUnavailableView("Connection Failed", systemImage: "xmark.octagon",
                                       description: Text(message))
                    .foregroundStyle(.white)
            case .closed:
                ContentUnavailableView("Session Closed", systemImage: "bolt.horizontal",
                                       description: Text("The remote shell ended."))
                    .foregroundStyle(.white)
            case .idleDisconnected:
                ContentUnavailableView {
                    Label("Disconnected due to inactivity", systemImage: "moon.zzz")
                } description: {
                    Text("This session was closed after being idle. You can change how long sessions stay connected.")
                } actions: {
                    Button("Change how long sessions stay connected") {
                        manager.requestOpenConnectionSettings = true
                        manager.minimize()   // dismiss the full-screen terminal cover
                    }
                }
                .foregroundStyle(.white)
            case .connected:
                EmptyView()
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
