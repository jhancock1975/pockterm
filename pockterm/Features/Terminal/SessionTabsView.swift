import SwiftUI
import SwiftData
import SwiftTerm

/// Hosts an existing `TerminalView` (owned by a session) inside SwiftUI.
struct TerminalHostView: UIViewRepresentable {
    let terminalView: TerminalView
    func makeUIView(context: Context) -> TerminalView { terminalView }
    func updateUIView(_ uiView: TerminalView, context: Context) {}
}

/// The full multi-session terminal surface: a tab strip over the active
/// session's terminal, accessory key bar, snippet runner, and host-key notice.
struct SessionTabsView: View {
    @Bindable var manager: SessionManager
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Snippet.label) private var snippets: [Snippet]

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
    }

    /// Compact single-row header: tab pills (× to close on the left + truncated
    /// name), the snippet runner, and an exit button — no oversized title bar.
    private var topBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(manager.sessions) { session in
                        tabPill(session)
                    }
                }
            }
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
            Button { manager.closeAll(); dismiss() } label: {
                Image(systemName: "chevron.down")
            }
        }
        .tint(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black)
    }

    private func tabPill(_ session: TerminalSession) -> some View {
        let isActive = session.id == manager.activeID
        return HStack(spacing: 6) {
            Button { manager.close(session) } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .bold))
            }
            .buttonStyle(.plain)
            Text(session.title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: 170)
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
