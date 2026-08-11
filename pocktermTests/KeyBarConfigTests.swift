import Foundation
import Testing
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
