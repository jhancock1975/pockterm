import SwiftUI
import UIKit
import SwiftTerm

/// The phone's keyboard, for a terminal that's drawn on the glasses.
///
/// iPhone external displays are display-only: a view there can't bring up the
/// keyboard. So in glasses mode this invisible view on the phone is first
/// responder instead. It carries the session's key bar and forwards every
/// piece of input (typed text, Backspace, CJK composition, hardware keys) to
/// the terminal. SwiftTerm's input methods don't check whether the terminal
/// itself is first responder, which is what makes forwarding enough.
final class TerminalKeyboardProxy: UIView, UITextInput {
    /// Where typing goes. Changing it hands focus over and swaps in the new
    /// session's key bar.
    var target: TerminalView? {
        didSet {
            guard target !== oldValue else { return }
            if let oldValue {
                if isFirstResponder { release(oldValue) }
                if oldValue.inputDelegate === relay { oldValue.inputDelegate = nil }
            }
            target?.inputDelegate = relay
            if isFirstResponder, let target { claim(target) }
            // On the next turn, not now. This runs inside SwiftUI's view update
            // (KeyboardProxyHost), and reloading input views animates the
            // keyboard, whose tracking calls back into SwiftUI mid-update.
            // Closing an exited session in glasses mode hung the app on the
            // resulting AttributeGraph cycle.
            DispatchQueue.main.async { [weak self] in self?.reloadInputViews() }
        }
    }

    /// Told whenever the keyboard comes or goes, so the phone can offer a way
    /// to bring it back.
    var onFocusChange: ((Bool) -> Void)?

    private let relay = InputDelegateRelay()
    private var wantsFocus = false
    private var focusAttempts = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        relay.proxy = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Focus

    /// Takes the keyboard now if it can, or as soon as it's in a window and
    /// nothing is animating over it. An alert that's still animating away
    /// refuses to give up first responder.
    func requestFocus() {
        wantsFocus = true
        focusAttempts = 0
        attemptFocus()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attemptFocus()
    }

    private func attemptFocus() {
        guard wantsFocus, window != nil, target != nil else { return }
        var top = window?.rootViewController
        while let next = top?.presentedViewController { top = next }
        if let transition = top?.transitionCoordinator {
            transition.animate(alongsideTransition: nil) { [weak self] _ in self?.attemptFocus() }
            return
        }
        // Something is up over the phone (the assistant, an alert, a sheet):
        // leave its keyboard alone. Plugging the glasses in under the
        // assistant used to take its keyboard, so the question being typed
        // went into the live shell. Show Keyboard asks again once it's gone.
        if let top, !isDescendant(of: top.view) {
            wantsFocus = false
            return
        }
        if becomeFirstResponder() {
            wantsFocus = false
        } else if focusAttempts < 5 {
            focusAttempts += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.attemptFocus() }
        }
    }

    override var canBecomeFirstResponder: Bool { target != nil }

    override var inputAccessoryView: UIView? { target?.inputAccessoryView }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        if let target { claim(target) }
        onFocusChange?(true)
        return true
    }

    override func resignFirstResponder() -> Bool {
        guard super.resignFirstResponder() else { return false }
        if let target { release(target) }
        onFocusChange?(false)
        return true
    }

    /// While the keyboard is held for it, the terminal behaves as focused: the
    /// caret blinks, and apps that ask (tmux, vim) get their focus-in event.
    private func claim(_ terminal: TerminalView) {
        terminal.caretViewTracksFocus = false
        terminal.getTerminal().setTerminalFocus(true)
    }

    private func release(_ terminal: TerminalView) {
        terminal.caretViewTracksFocus = true
        terminal.getTerminal().setTerminalFocus(false)
    }

    // MARK: Paste
    //
    // Cmd-V and the three-finger paste gesture go to the first responder,
    // which in glasses mode is this view rather than the terminal.

    override func paste(_ sender: Any?) { target?.paste(sender) }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(paste(_:)) { return target != nil }
        return super.canPerformAction(action, withSender: sender)
    }

    // MARK: Hardware keyboard

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let target else { return super.pressesBegan(presses, with: event) }
        target.pressesBegan(presses, with: event)
    }

    override func pressesChanged(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let target else { return super.pressesChanged(presses, with: event) }
        target.pressesChanged(presses, with: event)
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let target else { return super.pressesEnded(presses, with: event) }
        target.pressesEnded(presses, with: event)
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        guard let target else { return super.pressesCancelled(presses, with: event) }
        target.pressesCancelled(presses, with: event)
    }

    // MARK: UITextInputTraits: the terminal's own, so the keyboard is identical
    //
    // @objc because UIKit reads these through the Objective-C runtime, and
    // these optional protocol properties aren't exposed to it otherwise. Without
    // it UIKit saw none of them and used its defaults: autocorrect, predictive
    // text, and a capital letter at the start of every line.

    @objc var keyboardType: UIKeyboardType { target?.keyboardType ?? .default }
    @objc var keyboardAppearance: UIKeyboardAppearance { target?.keyboardAppearance ?? .default }
    @objc var returnKeyType: UIReturnKeyType { target?.returnKeyType ?? .default }
    @objc var autocapitalizationType: UITextAutocapitalizationType { target?.autocapitalizationType ?? .none }
    @objc var autocorrectionType: UITextAutocorrectionType { target?.autocorrectionType ?? .no }
    @objc var spellCheckingType: UITextSpellCheckingType { target?.spellCheckingType ?? .no }
    @objc var smartQuotesType: UITextSmartQuotesType { target?.smartQuotesType ?? .no }
    @objc var smartDashesType: UITextSmartDashesType { target?.smartDashesType ?? .no }
    @objc var smartInsertDeleteType: UITextSmartInsertDeleteType { target?.smartInsertDeleteType ?? .no }

    // MARK: UIKeyInput

    var hasText: Bool { target?.hasText ?? false }
    func insertText(_ text: String) { target?.insertText(text) }
    func deleteBackward() { target?.deleteBackward() }

    // MARK: UITextInput: text and positions, all the terminal's

    func text(in range: UITextRange) -> String? { target?.text(in: range) }
    func replace(_ range: UITextRange, withText text: String) { target?.replace(range, withText: text) }

    var selectedTextRange: UITextRange? {
        get { target?.selectedTextRange }
        set { target?.selectedTextRange = newValue }
    }
    var markedTextRange: UITextRange? { target?.markedTextRange }
    var markedTextStyle: [NSAttributedString.Key: Any]? {
        get { target?.markedTextStyle }
        set { target?.markedTextStyle = newValue }
    }
    func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        target?.setMarkedText(markedText, selectedRange: selectedRange)
    }
    func unmarkText() { target?.unmarkText() }

    var beginningOfDocument: UITextPosition { target?.beginningOfDocument ?? UITextPosition() }
    var endOfDocument: UITextPosition { target?.endOfDocument ?? UITextPosition() }

    func textRange(from fromPosition: UITextPosition, to toPosition: UITextPosition) -> UITextRange? {
        target?.textRange(from: fromPosition, to: toPosition)
    }
    func position(from position: UITextPosition, offset: Int) -> UITextPosition? {
        target?.position(from: position, offset: offset)
    }
    func position(from position: UITextPosition, in direction: UITextLayoutDirection,
                  offset: Int) -> UITextPosition? {
        target?.position(from: position, in: direction, offset: offset)
    }
    func compare(_ position: UITextPosition, to other: UITextPosition) -> ComparisonResult {
        target?.compare(position, to: other) ?? .orderedSame
    }
    func offset(from: UITextPosition, to toPosition: UITextPosition) -> Int {
        target?.offset(from: from, to: toPosition) ?? 0
    }
    func position(within range: UITextRange, farthestIn direction: UITextLayoutDirection) -> UITextPosition? {
        target?.position(within: range, farthestIn: direction)
    }
    func characterRange(byExtending position: UITextPosition,
                        in direction: UITextLayoutDirection) -> UITextRange? {
        target?.characterRange(byExtending: position, in: direction)
    }

    var inputDelegate: UITextInputDelegate? {
        get { relay.system }
        set { relay.system = newValue }
    }

    lazy var tokenizer: UITextInputTokenizer = UITextInputStringTokenizer(textInput: self)

    func baseWritingDirection(for position: UITextPosition,
                              in direction: UITextStorageDirection) -> NSWritingDirection { .leftToRight }
    func setBaseWritingDirection(_ writingDirection: NSWritingDirection, for range: UITextRange) {}

    // MARK: UITextInput geometry
    //
    // The terminal is on another screen, so rectangles in its coordinates mean
    // nothing here. Anything the system anchors to text (the candidate bar,
    // the loupe) anchors to this view instead.

    func firstRect(for range: UITextRange) -> CGRect { bounds }
    func caretRect(for position: UITextPosition) -> CGRect {
        CGRect(x: 0, y: 0, width: 1, height: max(bounds.height, 1))
    }
    func selectionRects(for range: UITextRange) -> [UITextSelectionRect] { [] }
    func closestPosition(to point: CGPoint) -> UITextPosition? { nil }
    func closestPosition(to point: CGPoint, within range: UITextRange) -> UITextPosition? { nil }
    func characterRange(at point: CGPoint) -> UITextRange? { nil }
}

/// Sits between the terminal and the system's text-input machinery. The
/// terminal announces changes with itself as the sender, but the system only
/// listens to its first responder, the proxy. So each notification is re-sent
/// as coming from the proxy.
private final class InputDelegateRelay: NSObject, UITextInputDelegate {
    weak var proxy: TerminalKeyboardProxy?
    weak var system: UITextInputDelegate?

    func selectionWillChange(_ textInput: UITextInput?) { system?.selectionWillChange(proxy) }
    func selectionDidChange(_ textInput: UITextInput?) { system?.selectionDidChange(proxy) }
    func textWillChange(_ textInput: UITextInput?) { system?.textWillChange(proxy) }
    func textDidChange(_ textInput: UITextInput?) { system?.textDidChange(proxy) }
    @available(iOS 18.4, *)
    func conversationContext(_ context: UIConversationContext?, didChange textInput: UITextInput?) {
        system?.conversationContext(context, didChange: proxy)
    }
}

/// Puts a `TerminalKeyboardProxy` in the SwiftUI tree. Changing
/// `focusRequest` asks for the keyboard.
struct KeyboardProxyHost: UIViewRepresentable {
    let terminalView: TerminalView
    let focusRequest: Int
    let onFocusChange: (Bool) -> Void

    final class Coordinator { var handledRequest: Int? }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> TerminalKeyboardProxy {
        TerminalKeyboardProxy(frame: .zero)
    }

    func updateUIView(_ proxy: TerminalKeyboardProxy, context: Context) {
        // Focus can change during this very update (requestFocus below, or the
        // view joining its window), and SwiftUI state mustn't be written then.
        let onFocusChange = onFocusChange
        proxy.onFocusChange = { up in DispatchQueue.main.async { onFocusChange(up) } }
        proxy.target = terminalView
        if context.coordinator.handledRequest != focusRequest {
            context.coordinator.handledRequest = focusRequest
            proxy.requestFocus()
        }
    }

    static func dismantleUIView(_ proxy: TerminalKeyboardProxy, coordinator: Coordinator) {
        // Silently: this runs mid-update, when state changes aren't allowed,
        // and on unplug the phone still needs to know the keyboard was up.
        proxy.onFocusChange = nil
        _ = proxy.resignFirstResponder()
        proxy.target = nil
    }
}
