import Foundation
import SwiftTerm
import Testing
import UIKit
@testable import pockterm

@Test @MainActor func hideKeyboardIsNotUserConfigurable() {
    // It is pinned to the trailing edge of the bar, so the layout must not be
    // able to place, move, or remove it.
    #expect(!KeyBarConfig.configurableKeys.contains(.hideKeyboard))
    #expect(!KeyBarConfig.defaultKeys.contains(.hideKeyboard))
}

@Test @MainActor func configurableKeysCoverEverythingElse() {
    let expected = Set(KeyBarKey.allCases).subtracting([.hideKeyboard])
    #expect(Set(KeyBarConfig.configurableKeys) == expected)
}

@Test @MainActor func defaultKeysAreAllConfigurable() {
    for key in KeyBarConfig.defaultKeys {
        #expect(KeyBarConfig.configurableKeys.contains(key))
    }
}

/// A layout saved before hideKeyboard became pinned still lists it. It must
/// survive loading — the bar filters it out when building the row — rather than
/// invalidating the whole saved layout.
@Test @MainActor func legacyLayoutContainingHideKeyboardStillLoads() {
    let raw = ["esc", "ctrl", "hideKeyboard", "tab"]
    let keys = raw.compactMap(KeyBarKey.init(rawValue:))
    #expect(keys == [.esc, .ctrl, .hideKeyboard, .tab])
    #expect(keys.filter { $0 != .hideKeyboard } == [.esc, .ctrl, .tab])
}

// MARK: Pinned dismiss chip

nonisolated private let barWidth: CGFloat = 393     // iPhone 17 portrait
nonisolated private let narrowestBarWidth: CGFloat = 375   // iPhone SE, the narrowest on iOS 26

@MainActor
private func laidOutKeyBar(width: CGFloat = barWidth) -> KeyBarView {
    let terminal = TerminalView(frame: CGRect(x: 0, y: 0, width: width, height: 600))
    let bar = KeyBarView(terminalView: terminal)
    bar.frame = CGRect(x: 0, y: 0, width: width, height: 48)
    bar.setNeedsLayout()
    bar.layoutIfNeeded()
    return bar
}

/// The chip is a blurred pad drawn above the scrolling keys. If it lays out at
/// zero width there is nothing to tap and nothing for the keys to slide under,
/// which is the whole point of pinning it.
@Test @MainActor func dismissChipHasTappableWidthAtTheTrailingEdge() {
    let bar = laidOutKeyBar()
    let pad = try! #require(bar.subviews.compactMap { $0 as? UIVisualEffectView }.first)

    #expect(pad.bounds.width >= 44)
    #expect(pad.bounds.height == bar.bounds.height)
    #expect(abs(pad.frame.maxX - bar.bounds.width) < 0.5)
}

/// The button inside the pad has to be laid out too — a zero-frame button
/// leaves a blurred sliver with no icon in it.
@Test @MainActor func dismissChipButtonIsLaidOutInsideThePad() {
    let bar = laidOutKeyBar()
    let pad = try! #require(bar.subviews.compactMap { $0 as? UIVisualEffectView }.first)
    let button = try! #require(pad.contentView.subviews.compactMap { $0 as? UIButton }.first)

    #expect(button.bounds.width >= 44)
    #expect(button.bounds.height > 0)
    #expect(pad.contentView.bounds.contains(button.frame))
}

/// The scroll view reserves the chip's width so the last key can be scrolled
/// clear of it instead of sitting permanently underneath.
@Test @MainActor func keysCanScrollClearOfTheChip() {
    let bar = laidOutKeyBar()
    let pad = try! #require(bar.subviews.compactMap { $0 as? UIVisualEffectView }.first)
    let scroll = try! #require(bar.subviews.compactMap { $0 as? UIScrollView }.first)

    #expect(scroll.contentInset.right == pad.bounds.width)
}

// MARK: Arrows reachable without scrolling

/// The arrows are the most-used keys on the bar, and only about six keys fit
/// before the trailing edge on the narrowest iPhone. For most of 1.x the
/// default layout spent those slots on `esc ctrl meta tab ~ |`, which left every
/// arrow off-screen behind a horizontal swipe that nothing advertises.
@Test(arguments: [barWidth, narrowestBarWidth]) @MainActor func defaultLayoutKeepsTheArrowsOnScreen(width: CGFloat) {
    KeyBarConfig.save(KeyBarConfig.defaultKeys)
    let bar = laidOutKeyBar(width: width)
    let scroll = try! #require(bar.subviews.compactMap { $0 as? UIScrollView }.first)
    let stack = try! #require(scroll.subviews.compactMap { $0 as? UIStackView }.first)

    // At rest the scroll view shows content up to its own width, less the
    // reserved strip the pinned dismiss chip occupies.
    let visibleWidth = scroll.bounds.width - scroll.contentInset.right
    let laidOut = KeyBarConfig.defaultKeys.filter { $0 != .hideKeyboard }

    for arrow in [KeyBarKey.left, .down, .up, .right] {
        let index = try! #require(laidOut.firstIndex(of: arrow))
        let button = stack.arrangedSubviews[index]
        let frame = button.convert(button.bounds, to: scroll)
        // With a cushion, not merely inside the edge: a layout that fits by a
        // point is one SF Symbol metric change away from clipping again.
        #expect(frame.maxX <= visibleWidth - 4,
                "\(arrow) ends at \(frame.maxX) of \(visibleWidth) visible at \(width) pt")
    }
}

// MARK: Backspace

/// The point of having backspace on the bar at all is that its repeat is ours
/// (450ms delay, 80ms interval) rather than the software keyboard's.
@Test @MainActor func backspaceRepeatsAndSendsDEL() {
    #expect(KeyBarKey.backspace.repeats)
    #expect(KeyBarKey.backspace.bytes(applicationCursor: false) == [0x7f])
    #expect(KeyBarKey.backspace.bytes(applicationCursor: true) == [0x7f])
    #expect(KeyBarConfig.defaultKeys.contains(.backspace))
}

// MARK: Keys added after a layout was saved

/// A `UserDefaults` of its own per test — these run in parallel, and a shared
/// store (or a shared settable one on `KeyBarConfig`) has them reading each
/// other's layouts.
private func withEphemeralDefaults(_ body: (UserDefaults) -> Void) {
    let name = "pockterm.tests.\(UUID().uuidString)"
    let suite = UserDefaults(suiteName: name)!
    defer { UserDefaults.standard.removePersistentDomain(forName: name) }
    body(suite)
}

/// The layout an early-1.x user is still carrying: customized (esc moved to
/// the end) and saved before backspace existed as a key at all. This is the
/// one that was actually on the phone.
private let layoutSavedBeforeBackspace = [
    "meta", "ctrl", "tab", "tilde", "pipe", "slash", "dash",
    "left", "down", "up", "right", "pageUp", "pageDown", "f1", "esc", "hideKeyboard",
]

/// #66 put a repeating Backspace in `defaultKeys`, but `load()` returns a saved
/// layout verbatim — so the bar of everyone who had ever customized it, the
/// user who asked for the key included, still had no backspace on it. A key
/// added to the bar after a layout was saved has to be merged into that layout.
@Test @MainActor func savedLayoutFromBeforeBackspaceGainsIt() {
    withEphemeralDefaults { suite in
        suite.set(layoutSavedBeforeBackspace, forKey: "keyBarKeys")

        let migrated = KeyBarConfig.load(from: suite)
        // At the front, not appended: six or seven keys fit before the trailing
        // edge, and a 16-key bar would hide the new key behind a swipe.
        #expect(migrated.first == .backspace)
        // Their own layout is otherwise untouched — same keys, same order.
        #expect(migrated.dropFirst().map(\.rawValue) == layoutSavedBeforeBackspace)
        // Persisted, so the Key Bar settings screen agrees with the bar.
        #expect(suite.stringArray(forKey: "keyBarKeys")?.first == "backspace")
    }
}

/// The merge runs once. Otherwise the key could never be taken off the bar: it
/// would be back on the next load.
@Test @MainActor func removingBackspaceAfterTheMergeSticks() {
    withEphemeralDefaults { suite in
        suite.set(layoutSavedBeforeBackspace, forKey: "keyBarKeys")
        var keys = KeyBarConfig.load(from: suite)

        keys.removeAll { $0 == .backspace }
        KeyBarConfig.save(keys, to: suite)

        #expect(!KeyBarConfig.load(from: suite).contains(.backspace))
    }
}

/// A user who never customized the bar gets `defaultKeys`, which already has
/// backspace in its tested position — the merge must not move it to the front.
@Test @MainActor func untouchedBarKeepsTheDefaultOrder() {
    withEphemeralDefaults { suite in
        #expect(KeyBarConfig.load(from: suite) == KeyBarConfig.defaultKeys)
    }
}

/// A layout saved with backspace already in it is left exactly as arranged.
@Test @MainActor func savedLayoutThatAlreadyHasBackspaceIsUntouched() {
    withEphemeralDefaults { suite in
        let saved = ["esc", "ctrl", "backspace", "left", "right"]
        suite.set(saved, forKey: "keyBarKeys")
        #expect(KeyBarConfig.load(from: suite).map(\.rawValue) == saved)
    }
}

/// The merge itself, without a store in the way.
@Test @MainActor func mergeOnlyAddsWhatWasNeverOffered() {
    #expect(KeyBarConfig.merging(saved: [.esc, .ctrl], alreadyOffered: []) == [.backspace, .esc, .ctrl])
    #expect(KeyBarConfig.merging(saved: [.esc, .ctrl], alreadyOffered: ["backspace"]) == [.esc, .ctrl])
    #expect(KeyBarConfig.merging(saved: [.esc, .backspace], alreadyOffered: []) == [.esc, .backspace])
}


// MARK: - PgUp/PgDn in glasses mode

@Test @MainActor func pageKeysScrollLocallyInGlassesMode() {
    // Nothing on the glasses can be swiped, so these are the way back
    // through scrollback, the way SwiftTerm treats a hardware PgUp.
    #expect(KeyBarKey.pageUp.localScroll(applicationCursor: false, scrollsLocally: true) == .up)
    #expect(KeyBarKey.pageDown.localScroll(applicationCursor: false, scrollsLocally: true) == .down)
}

@Test @MainActor func fullScreenAppsStillGetThePageKeys() {
    // less, vim and tmux switch the terminal to application cursor mode.
    #expect(KeyBarKey.pageUp.localScroll(applicationCursor: true, scrollsLocally: true) == nil)
}

@Test @MainActor func thePhoneKeepsSendingThePageKeys() {
    #expect(KeyBarKey.pageUp.localScroll(applicationCursor: false, scrollsLocally: false) == nil)
    #expect(KeyBarKey.up.localScroll(applicationCursor: false, scrollsLocally: true) == nil)
}

/// Collects what the terminal would send to the server.
private final class SentBytes: NSObject, TerminalViewDelegate {
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

@MainActor
private func button(_ label: String, in view: UIView) -> UIButton? {
    if let button = view as? UIButton, button.accessibilityLabel == label { return button }
    for sub in view.subviews { if let found = button(label, in: sub) { return found } }
    return nil
}

@Test @MainActor func theKeyBarsPgUpPagesBackThroughScrollbackInGlassesMode() throws {
    // The real button, the real terminal: a shell prompt below 200 lines of
    // output, as after a long build.
    let terminal = TerminalView(frame: CGRect(x: 0, y: 0, width: 393, height: 300))
    let sent = SentBytes()
    terminal.terminalDelegate = sent
    terminal.feed(text: (1...200).map(String.init).joined(separator: "\r\n") + "\r\n% ")
    let bar = KeyBarView(terminalView: terminal)
    bar.scrollsLocally = true
    let pgUp = try #require(button("PgUp", in: bar))
    let bottom = terminal.scrollPosition

    pgUp.sendActions(for: .touchDown)
    pgUp.sendActions(for: .touchUpInside)

    #expect(terminal.scrollPosition < bottom, "still at \(terminal.scrollPosition)")
    #expect(sent.bytes.isEmpty, "PgUp went to the server instead")
}
