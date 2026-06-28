import SwiftUI

/// Scrollable bar of special keys above the keyboard, mirroring Termius's
/// terminal accessory row. `ctrlActive` latches the next byte into a control
/// character (handled by the session view).
struct TerminalKeyAccessoryBar: View {
    let send: ([UInt8]) -> Void
    @Binding var ctrlActive: Bool

    private func bytes(_ s: String) { send(Array(s.utf8)) }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                key("esc") { bytes("\u{1b}") }
                Toggle("ctrl", isOn: $ctrlActive)
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
    }

    private func key(_ label: String, _ action: @escaping () -> Void) -> some View {
        Button(label, action: action)
            .font(.system(.callout, design: .monospaced))
            .buttonStyle(.bordered)
    }
}
