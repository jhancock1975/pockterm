import SwiftUI

/// Everything the glasses show: the active session's terminal, full screen
/// and nothing else, or an idle screen when there's no terminal to show.
struct GlassesRootView: View {
    let manager: SessionManager
    let display: ExternalDisplay
    let sceneID: ObjectIdentifier

    var body: some View {
        ZStack {
            Color.black
            switch content {
            case .terminal(let id):
                if let session = manager.sessions.first(where: { $0.id == id }) {
                    ZStack {
                        TerminalHostView(terminalView: session.terminalView, avoidsKeyboard: false)
                        // Display-only here: its buttons are live on the phone.
                        SessionStatusView(session: session, manager: manager)
                            .environment(\.dynamicTypeSize, .accessibility2)
                            .allowsHitTesting(false)
                    }
                }
            case .idle:
                GlassesIdleView()
            }
        }
        .ignoresSafeArea()
    }

    private var content: GlassesContent {
        GlassesContent.resolve(isPrimary: display.isPrimary(sceneID),
                               activeID: manager.activeID,
                               sessionIDs: manager.sessions.map(\.id),
                               isMinimized: manager.isMinimized)
    }
}

/// The Pockterm mark (the same `>_` tile as pockterm.com) and one line saying
/// where to go next.
private struct GlassesIdleView: View {
    private static let tile = Color(red: 0.04, green: 0.07, blue: 0.13)
    private static let green = Color(red: 0.25, green: 0.82, blue: 0.50)

    var body: some View {
        VStack(spacing: 32) {
            RoundedRectangle(cornerRadius: 36)
                .fill(Self.tile)
                .frame(width: 160, height: 160)
                .overlay(Text(verbatim: ">_")
                    .font(.system(size: 76, weight: .bold, design: .monospaced))
                    .foregroundStyle(Self.green))
            Text("Open a session on your phone")
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
