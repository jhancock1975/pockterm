import SwiftUI

/// The phone's content area in glasses mode: the active session's files where
/// the terminal would be, and the keyboard typing into the terminal on the
/// glasses. While the session isn't connected, it shows the session's status
/// instead, with its buttons live.
///
/// Keyboard avoidance is manual, the same way AssistantView does it: iOS 26's
/// automatic avoidance uses a keyboard frame that leaves out the predictive
/// bar. SessionTabsView's root already ignores the keyboard safe area.
struct GlassesPhoneContent: View {
    let session: TerminalSession
    let manager: SessionManager
    /// Bumped by the top bar's Show Keyboard button.
    let focusRequest: Int
    @Binding var keyboardUp: Bool

    /// Bumped here when a file-browser text box closes.
    @State private var textEntryRefocus = 0
    @State private var containerBottom: CGFloat = 0
    @State private var keyboardTop: CGFloat = .infinity

    private var keyboardOverlap: CGFloat { max(0, containerBottom - keyboardTop) }

    var body: some View {
        ZStack {
            KeyboardProxyHost(terminalView: session.terminalView,
                              focusRequest: focusRequest &+ textEntryRefocus,
                              onFocusChange: { keyboardUp = $0 })
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if session.status == .connected {
                FilesBrowserView(model: session.files, embedded: true,
                                 onTextEntryEnded: { textEntryRefocus &+= 1 })
                    .id(session.id)
                    .environment(\.colorScheme, .dark)
                    .padding(.bottom, keyboardOverlap)
                    .animation(.easeOut(duration: 0.2), value: keyboardOverlap)
            } else {
                SessionStatusView(session: session, manager: manager)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(keyboardOverlapReader)
    }

    private var keyboardOverlapReader: some View {
        GeometryReader { geo in
            let bottom = geo.frame(in: .global).maxY
            Color.clear
                .onAppear { containerBottom = bottom }
                .onChange(of: bottom) { containerBottom = bottom }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillChangeFrameNotification)) { note in
                    guard let end = (note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey]
                                     as? NSValue)?.cgRectValue else { return }
                    keyboardTop = end.minY
                }
                .onReceive(NotificationCenter.default.publisher(
                    for: UIResponder.keyboardWillHideNotification)) { _ in
                    keyboardTop = .infinity
                }
        }
    }
}
