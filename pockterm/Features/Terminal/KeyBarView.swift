import UIKit
import SwiftTerm

/// The terminal's keyboard accessory bar: a horizontally scrollable row of
/// keys with a latching ctrl and meta, typematic repeat on movement keys, and
/// a user-customizable layout (see `KeyBarConfig`).
final class KeyBarView: UIInputView, UIInputViewAudioFeedback {
    private weak var terminalView: TerminalView?
    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    /// Sits above the scroll view on the trailing edge so the keys pass beneath
    /// it. Dismissing the keyboard must never require scrolling to find it.
    private let dismissPad = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
    private var ctrlButton: HighlightButton?
    private var metaButton: HighlightButton?

    private var repeatTimer: Timer?
    private var repeatDelayTask: Task<Void, Never>?

    var enableInputClicksWhenVisible: Bool { true }

    init(terminalView: TerminalView) {
        self.terminalView = terminalView
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 48), inputViewStyle: .keyboard)
        allowsSelfSizing = true

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.axis = .horizontal
        stack.spacing = 5
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        // Pinned dismiss button, added after the scroll view so it draws on top.
        let dismiss = makeButton(for: .hideKeyboard)
        dismissPad.translatesAutoresizingMaskIntoConstraints = false
        dismissPad.contentView.addSubview(dismiss)
        addSubview(dismissPad)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 5),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -5),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -6),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor, constant: -10),

            // Full bar height, so a key sliding under it disappears cleanly
            // rather than showing slivers above and below.
            dismissPad.topAnchor.constraint(equalTo: topAnchor),
            dismissPad.bottomAnchor.constraint(equalTo: bottomAnchor),
            dismissPad.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            dismiss.leadingAnchor.constraint(equalTo: dismissPad.leadingAnchor, constant: 6),
            dismiss.trailingAnchor.constraint(equalTo: dismissPad.trailingAnchor, constant: -6),
            dismiss.centerYAnchor.constraint(equalTo: dismissPad.centerYAnchor),
        ])

        reloadKeys()

        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(reloadKeys),
                           name: KeyBarConfig.changedNotification, object: nil)
        // SwiftTerm posts these when a latched modifier is consumed.
        center.addObserver(self, selector: #selector(syncModifierButtons),
                           name: Notification.Name("SwiftTerm.TerminalView.controlModifierReset"),
                           object: nil)
        center.addObserver(self, selector: #selector(syncModifierButtons),
                           name: Notification.Name("SwiftTerm.TerminalView.metaModifierReset"),
                           object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 48)
    }

    // MARK: Layout

    @objc private func reloadKeys() {
        cancelRepeat()
        ctrlButton = nil
        metaButton = nil
        for view in stack.arrangedSubviews { view.removeFromSuperview() }
        // hideKeyboard is pinned separately now; a saved layout from before that
        // change still contains it, so drop it here rather than draw it twice.
        for key in KeyBarConfig.load() where key != .hideKeyboard {
            let button = makeButton(for: key)
            stack.addArrangedSubview(button)
            if key == .esc {
                // Breathing room so esc is hard to fat-finger into ctrl.
                stack.setCustomSpacing(14, after: button)
            }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Let the last key scroll clear of the pinned button instead of ending
        // up permanently underneath it.
        let reserved = dismissPad.bounds.width
        if scrollView.contentInset.right != reserved {
            scrollView.contentInset.right = reserved
            scrollView.horizontalScrollIndicatorInsets.right = reserved
        }
    }

    private func makeButton(for key: KeyBarKey) -> UIButton {
        let button = HighlightButton(type: .system)
        var config = UIButton.Configuration.gray()
        config.baseForegroundColor = .label
        config.background.backgroundColor = UIColor(white: 0.28, alpha: 1)
        config.cornerStyle = .medium
        if let title = key.title {
            config.attributedTitle = AttributedString(
                title, attributes: AttributeContainer([.font: UIFont.systemFont(ofSize: 15)]))
        }
        if let symbol = key.systemImage {
            config.image = UIImage(systemName: symbol,
                                   withConfiguration: UIImage.SymbolConfiguration(pointSize: 14))
        }
        // Generous hit area; esc gets extra width so it's easy to hit.
        let horizontalPad: CGFloat = key == .esc ? 22 : 10
        config.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: horizontalPad,
                                                       bottom: 8, trailing: horizontalPad)
        button.configuration = config
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: key == .esc ? 72 : 44).isActive = true

        switch key {
        case .ctrl:
            ctrlButton = button
            button.addTarget(self, action: #selector(toggleCtrl), for: .touchDown)
        case .meta:
            metaButton = button
            button.addTarget(self, action: #selector(toggleMeta), for: .touchDown)
        case .hideKeyboard:
            button.addTarget(self, action: #selector(hideKeyboard), for: .touchDown)
        default:
            button.key = key
            button.addTarget(self, action: #selector(keyDown(_:)), for: .touchDown)
            if key.repeats {
                for event: UIControl.Event in [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit] {
                    button.addTarget(self, action: #selector(keyUp), for: event)
                }
            }
        }
        return button
    }

    // MARK: Key actions

    @objc private func keyDown(_ sender: HighlightButton) {
        guard let key = sender.key else { return }
        if key.repeats {
            startRepeating { [weak self] in self?.fire(key) }
        } else {
            fire(key)
        }
    }

    @objc private func keyUp() {
        cancelRepeat()
    }

    private func fire(_ key: KeyBarKey) {
        UIDevice.current.playInputClick()
        guard let terminalView else { return }
        if let text = key.insertedText {
            // Through insertText so a latched ctrl/meta applies to it.
            terminalView.insertText(text)
        } else if let bytes = key.bytes(applicationCursor: terminalView.getTerminal().applicationCursor) {
            terminalView.send(bytes)
        }
    }

    @objc private func toggleCtrl() {
        UIDevice.current.playInputClick()
        terminalView?.controlModifier.toggle()
        syncModifierButtons()
    }

    @objc private func toggleMeta() {
        UIDevice.current.playInputClick()
        terminalView?.metaModifier.toggle()
        syncModifierButtons()
    }

    @objc private func syncModifierButtons() {
        ctrlButton?.setHighlightedState(terminalView?.controlModifier ?? false)
        metaButton?.setHighlightedState(terminalView?.metaModifier ?? false)
    }

    @objc private func hideKeyboard() {
        UIDevice.current.playInputClick()
        _ = terminalView?.resignFirstResponder()
    }

    // MARK: Typematic

    private func startRepeating(_ action: @escaping () -> Void) {
        cancelRepeat()
        action()
        repeatDelayTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.repeatTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
                    action()
                }
            }
        }
    }

    private func cancelRepeat() {
        repeatDelayTask?.cancel()
        repeatDelayTask = nil
        repeatTimer?.invalidate()
        repeatTimer = nil
    }
}

/// Button that remembers its key and can show a "latched" tint.
private final class HighlightButton: UIButton {
    var key: KeyBarKey?

    func setHighlightedState(_ active: Bool) {
        configuration?.background.backgroundColor =
            active ? tintColor : UIColor(white: 0.28, alpha: 1)
    }
}
