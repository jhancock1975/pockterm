import SwiftUI
import SwiftTerm

/// Bridges SwiftTerm's UIKit `TerminalView` into SwiftUI. Keystrokes and size
/// changes are reported through callbacks; `onReady` hands the live terminal
/// back to the caller so it can feed received bytes into it.
struct SwiftTermView: UIViewRepresentable {
    let onInput: ([UInt8]) -> Void
    let onSizeChange: (Int, Int) -> Void
    let onReady: (TerminalView) -> Void

    func makeUIView(context: Context) -> TerminalView {
        let view = TerminalView()
        view.terminalDelegate = context.coordinator
        view.backgroundColor = .black
        onReady(view)
        return view
    }

    func updateUIView(_ uiView: TerminalView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onInput: onInput, onSizeChange: onSizeChange)
    }

    final class Coordinator: NSObject, TerminalViewDelegate {
        let onInput: ([UInt8]) -> Void
        let onSizeChange: (Int, Int) -> Void

        init(onInput: @escaping ([UInt8]) -> Void, onSizeChange: @escaping (Int, Int) -> Void) {
            self.onInput = onInput
            self.onSizeChange = onSizeChange
        }

        func send(source: TerminalView, data: ArraySlice<UInt8>) { onInput(Array(data)) }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) { onSizeChange(newCols, newRows) }
        func scrolled(source: TerminalView, position: Double) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
        func bell(source: TerminalView) {}
        func clipboardCopy(source: TerminalView, content: Data) {}
        func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }
}
