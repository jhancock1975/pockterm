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

// MARK: - Keyboard traits UIKit actually sees

@Test @MainActor func uikitSeesTheTerminalsKeyboardTraits() {
    // UIKit reads these through the Objective-C runtime. If it can't see them
    // it falls back to its defaults: autocorrect, predictive text and a
    // capital letter at the start of every line.
    let (view, _) = terminal()
    let proxy = proxy(for: view)
    for name in ["autocorrectionType", "autocapitalizationType", "spellCheckingType",
                 "smartQuotesType", "smartDashesType", "smartInsertDeleteType", "keyboardType"] {
        #expect(proxy.responds(to: NSSelectorFromString(name)), "\(name) invisible to UIKit")
    }
    #expect((proxy.value(forKey: "autocorrectionType") as? Int) == UITextAutocorrectionType.no.rawValue)
    #expect((proxy.value(forKey: "autocapitalizationType") as? Int) == UITextAutocapitalizationType.none.rawValue)
}

// MARK: - Paste

@Test @MainActor func pasteReachesTheTerminal() {
    // Cmd-V on a hardware keyboard and the three-finger paste gesture both
    // send paste: to the first responder, which in glasses mode is the proxy.
    let (view, capture) = terminal()
    UIPasteboard.general.string = "echo pasted"
    proxy(for: view).paste(nil)
    #expect(capture.bytes == Array("echo pasted".utf8))
}

@Test @MainActor func theSystemOffersPasteOnlyWithATerminal() {
    let paste = #selector(UIResponderStandardEditActions.paste(_:))
    let (view, _) = terminal()
    #expect(proxy(for: view).canPerformAction(paste, withSender: nil))
    #expect(!TerminalKeyboardProxy(frame: .zero).canPerformAction(paste, withSender: nil))
}

@Test @MainActor func pastedTextIsPlainByDefault() {
    let (view, capture) = terminal()
    view.paste(text: "ls")
    #expect(capture.bytes == Array("ls".utf8))
}

@Test @MainActor func pastedTextIsBracketedWhenTheAppAsks() {
    let (view, capture) = terminal()
    view.feed(text: "\u{1b}[?2004h")   // zsh, bash and vim turn this on
    view.paste(text: "ls")
    #expect(capture.bytes == Array("\u{1b}[200~ls\u{1b}[201~".utf8))
}

// MARK: - Not taking the keyboard from something over the phone

/// Reports something presented over it, without the animation a real
/// presentation needs.
@MainActor
private final class Covered: UIViewController {
    var cover: UIViewController?
    override var presentedViewController: UIViewController? { cover }
}

@Test @MainActor func aSheetOverThePhoneKeepsItsKeyboard() throws {
    // Plugging the glasses in under the assistant used to hand its keyboard
    // to the proxy, so the question being typed went into the live shell.
    let scene = try #require(UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }.first)
    let window = UIWindow(windowScene: scene)
    let root = Covered()
    window.rootViewController = root
    window.makeKeyAndVisible()
    defer { window.isHidden = true }
    let (view, _) = terminal()
    let proxy = proxy(for: view)
    root.view.addSubview(proxy)
    defer { _ = proxy.resignFirstResponder() }

    root.cover = UIViewController()
    proxy.requestFocus()
    #expect(!proxy.isFirstResponder)

    // Once it's gone, Show Keyboard brings the keyboard back.
    root.cover = nil
    proxy.requestFocus()
    #expect(proxy.isFirstResponder)
}
