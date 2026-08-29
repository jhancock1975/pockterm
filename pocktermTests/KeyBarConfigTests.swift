import Foundation
import SwiftTerm
import Testing
import UIKit
@testable import pockterm

@Test func hideKeyboardIsNotUserConfigurable() {
    // It is pinned to the trailing edge of the bar, so the layout must not be
    // able to place, move, or remove it.
    #expect(!KeyBarConfig.configurableKeys.contains(.hideKeyboard))
    #expect(!KeyBarConfig.defaultKeys.contains(.hideKeyboard))
}

@Test func configurableKeysCoverEverythingElse() {
    let expected = Set(KeyBarKey.allCases).subtracting([.hideKeyboard])
    #expect(Set(KeyBarConfig.configurableKeys) == expected)
}

@Test func defaultKeysAreAllConfigurable() {
    for key in KeyBarConfig.defaultKeys {
        #expect(KeyBarConfig.configurableKeys.contains(key))
    }
}

/// A layout saved before hideKeyboard became pinned still lists it. It must
/// survive loading — the bar filters it out when building the row — rather than
/// invalidating the whole saved layout.
@Test func legacyLayoutContainingHideKeyboardStillLoads() {
    let raw = ["esc", "ctrl", "hideKeyboard", "tab"]
    let keys = raw.compactMap(KeyBarKey.init(rawValue:))
    #expect(keys == [.esc, .ctrl, .hideKeyboard, .tab])
    #expect(keys.filter { $0 != .hideKeyboard } == [.esc, .ctrl, .tab])
}

// MARK: Pinned dismiss chip

private let barWidth: CGFloat = 393     // iPhone 17 portrait
private let narrowestBarWidth: CGFloat = 375   // iPhone SE, the narrowest on iOS 26

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
@MainActor
@Test func dismissChipHasTappableWidthAtTheTrailingEdge() {
    let bar = laidOutKeyBar()
    let pad = try! #require(bar.subviews.compactMap { $0 as? UIVisualEffectView }.first)

    #expect(pad.bounds.width >= 44)
    #expect(pad.bounds.height == bar.bounds.height)
    #expect(abs(pad.frame.maxX - bar.bounds.width) < 0.5)
}

/// The button inside the pad has to be laid out too — a zero-frame button
/// leaves a blurred sliver with no icon in it.
@MainActor
@Test func dismissChipButtonIsLaidOutInsideThePad() {
    let bar = laidOutKeyBar()
    let pad = try! #require(bar.subviews.compactMap { $0 as? UIVisualEffectView }.first)
    let button = try! #require(pad.contentView.subviews.compactMap { $0 as? UIButton }.first)

    #expect(button.bounds.width >= 44)
    #expect(button.bounds.height > 0)
    #expect(pad.contentView.bounds.contains(button.frame))
}

/// The scroll view reserves the chip's width so the last key can be scrolled
/// clear of it instead of sitting permanently underneath.
@MainActor
@Test func keysCanScrollClearOfTheChip() {
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
@MainActor
@Test(arguments: [barWidth, narrowestBarWidth])
func defaultLayoutKeepsTheArrowsOnScreen(width: CGFloat) {
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
