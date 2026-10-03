import Testing
import UIKit
import SwiftTerm
@testable import pockterm

/// Collects what the terminal would send to the server. Not @MainActor, the
/// same as the app's TerminalDelegateProxy: SwiftTerm's delegate protocol
/// isn't actor-isolated.
private final class Capture: NSObject, TerminalViewDelegate {
    var bytes: [UInt8] = []
    func send(source: TerminalView, data: ArraySlice<UInt8>) { bytes += data }
    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    func scrolled(source: TerminalView, position: Double) {}
    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func clipboardCopy(source: TerminalView, content: Data) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

/// Records which object the system was told changed.
@MainActor
private final class DelegateSpy: NSObject, UITextInputDelegate {
    var senders: [AnyObject?] = []
    func selectionWillChange(_ textInput: UITextInput?) { senders.append(textInput as AnyObject?) }
    func selectionDidChange(_ textInput: UITextInput?) { senders.append(textInput as AnyObject?) }
    func textWillChange(_ textInput: UITextInput?) { senders.append(textInput as AnyObject?) }
    func textDidChange(_ textInput: UITextInput?) { senders.append(textInput as AnyObject?) }
    @available(iOS 18.4, *)
    func conversationContext(_ context: UIConversationContext?, didChange textInput: UITextInput?) {
        senders.append(textInput as AnyObject?)
    }
}

@MainActor
private func terminal() -> (TerminalView, Capture) {
    let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
    let capture = Capture()
    view.terminalDelegate = capture
    return (view, capture)
}

@MainActor
private func proxy(for view: TerminalView) -> TerminalKeyboardProxy {
    let proxy = TerminalKeyboardProxy(frame: .zero)
    proxy.target = view
    return proxy
}

@Test @MainActor func typedTextReachesTheServer() {
    let (view, capture) = terminal()
    proxy(for: view).insertText("ls -la")
    #expect(capture.bytes == Array("ls -la".utf8))
}

@Test @MainActor func backspaceWithNothingBufferedSendsDEL() {
    let (view, capture) = terminal()
    proxy(for: view).deleteBackward()
    #expect(capture.bytes == [0x7f])
}

@Test @MainActor func aJapaneseCompositionSendsNothingUntilItCommits() {
    let (view, capture) = terminal()
    let proxy = proxy(for: view)
    proxy.setMarkedText("に", selectedRange: NSRange(location: 1, length: 0))
    proxy.setMarkedText("日本", selectedRange: NSRange(location: 2, length: 0))
    #expect(capture.bytes.isEmpty)
    #expect(proxy.markedTextRange != nil)
    proxy.unmarkText()
    #expect(capture.bytes == Array("日本".utf8))
}

@Test @MainActor func theKeyBarTravelsWithTheTarget() {
    let (view, _) = terminal()
    let bar = UIView()
    view.inputAccessoryView = bar
    #expect(proxy(for: view).inputAccessoryView === bar)
}

@Test @MainActor func switchingTargetsSendsTypingToTheNewTerminal() {
    let (first, firstCapture) = terminal()
    let (second, secondCapture) = terminal()
    let proxy = proxy(for: first)
    proxy.target = second
    proxy.insertText("x")
    #expect(firstCapture.bytes.isEmpty)
    #expect(secondCapture.bytes == Array("x".utf8))
}

@Test @MainActor func theSystemHearsTerminalChangesAsComingFromTheProxy() {
    // The system only listens to its first responder, which is the proxy, so
    // the terminal's own change notifications have to arrive under its name.
    let (view, _) = terminal()
    let proxy = proxy(for: view)
    let spy = DelegateSpy()
    proxy.inputDelegate = spy
    view.inputDelegate?.textWillChange(view)
    #expect(spy.senders.count == 1)
    #expect(spy.senders.first! === proxy)
}

@Test @MainActor func withoutATargetTheProxyRefusesTheKeyboard() {
    #expect(!TerminalKeyboardProxy(frame: .zero).canBecomeFirstResponder)
}
