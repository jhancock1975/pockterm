import SwiftUI

/// The single scrollable bar of special keys above the keyboard. Every key
/// shares one style; `ctrl` latches the next byte into a control character and
/// fills in when active to show that state.
struct TerminalKeyAccessoryBar: View {
    let send: ([UInt8]) -> Void
    @Binding var ctrlActive: Bool

    private func bytes(_ s: String) { send(Array(s.utf8)) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                key("esc") { bytes("\u{1b}") }
                ctrlKey
                key("tab") { bytes("\t") }
                key("◀") { bytes("\u{1b}[D") }
                key("▼") { bytes("\u{1b}[B") }
                key("▲") { bytes("\u{1b}[A") }
                key("▶") { bytes("\u{1b}[C") }
                key("|") { bytes("|") }
                key("~") { bytes("~") }
                key("/") { bytes("/") }
                key("-") { bytes("-") }
                key("home") { bytes("\u{1b}[H") }
                key("end") { bytes("\u{1b}[F") }
                key("pgup") { bytes("\u{1b}[5~") }
                key("pgdn") { bytes("\u{1b}[6~") }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(.black)
    }

    /// Latching modifier key. Same shape/font as the others; fills when active.
    private var ctrlKey: some View {
        Button("ctrl") { ctrlActive.toggle() }
            .font(.system(.callout, design: .monospaced))
            .buttonStyle(.borderedProminent)
            .tint(ctrlActive ? Color.accentColor : Color(.tertiarySystemFill))
            .foregroundStyle(ctrlActive ? Color.white : Color.accentColor)
    }

    private func key(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.system(.callout, design: .monospaced))
            .buttonStyle(.borderedProminent)
            .tint(Color(.tertiarySystemFill))
            .foregroundStyle(Color.accentColor)
    }
}
