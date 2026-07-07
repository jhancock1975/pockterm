import Foundation
import SwiftTerm

/// One key that can appear on the terminal key bar.
enum KeyBarKey: String, CaseIterable, Codable, Identifiable {
    case esc, ctrl, meta, tab
    case tilde, pipe, slash, dash
    case left, down, up, right
    case pageUp, pageDown, home, end
    case f1, f2, f3, f4, f5, f6, f7, f8, f9, f10
    case hideKeyboard

    var id: String { rawValue }

    /// Text label, or nil when the key renders an SF Symbol instead.
    var title: String? {
        switch self {
        case .esc: return "esc"
        case .ctrl: return "ctrl"
        case .meta: return "meta"
        case .tilde: return "~"
        case .pipe: return "|"
        case .slash: return "/"
        case .dash: return "-"
        case .pageUp: return "PgUp"
        case .pageDown: return "PgDn"
        case .home: return "Home"
        case .end: return "End"
        case .f1: return "F1"
        case .f2: return "F2"
        case .f3: return "F3"
        case .f4: return "F4"
        case .f5: return "F5"
        case .f6: return "F6"
        case .f7: return "F7"
        case .f8: return "F8"
        case .f9: return "F9"
        case .f10: return "F10"
        case .tab, .left, .down, .up, .right, .hideKeyboard: return nil
        }
    }

    var systemImage: String? {
        switch self {
        case .tab: return "arrow.right.to.line.compact"
        case .left: return "arrow.left"
        case .down: return "arrow.down"
        case .up: return "arrow.up"
        case .right: return "arrow.right"
        case .hideKeyboard: return "keyboard.chevron.compact.down"
        default: return nil
        }
    }

    /// Name shown in the key bar customization screen.
    var displayName: String {
        switch self {
        case .tab: return "Tab"
        case .left: return "← Left"
        case .down: return "↓ Down"
        case .up: return "↑ Up"
        case .right: return "→ Right"
        case .hideKeyboard: return "Hide Keyboard"
        default: return title ?? rawValue
        }
    }

    /// Keys that auto-repeat while held (typematic).
    var repeats: Bool {
        switch self {
        case .tab, .left, .down, .up, .right, .pageUp, .pageDown: return true
        default: return false
        }
    }

    /// Bytes to send for byte-producing keys. Arrow/home/end sequences depend
    /// on the terminal's application-cursor mode.
    func bytes(applicationCursor: Bool) -> [UInt8]? {
        switch self {
        case .esc: return [0x1b]
        case .tab: return [0x09]
        case .left: return applicationCursor ? EscapeSequences.moveLeftApp : EscapeSequences.moveLeftNormal
        case .down: return applicationCursor ? EscapeSequences.moveDownApp : EscapeSequences.moveDownNormal
        case .up: return applicationCursor ? EscapeSequences.moveUpApp : EscapeSequences.moveUpNormal
        case .right: return applicationCursor ? EscapeSequences.moveRightApp : EscapeSequences.moveRightNormal
        case .pageUp: return EscapeSequences.cmdPageUp
        case .pageDown: return EscapeSequences.cmdPageDown
        case .home: return applicationCursor ? EscapeSequences.moveHomeApp : EscapeSequences.moveHomeNormal
        case .end: return applicationCursor ? EscapeSequences.moveEndApp : EscapeSequences.moveEndNormal
        case .f1: return EscapeSequences.cmdF[0]
        case .f2: return EscapeSequences.cmdF[1]
        case .f3: return EscapeSequences.cmdF[2]
        case .f4: return EscapeSequences.cmdF[3]
        case .f5: return EscapeSequences.cmdF[4]
        case .f6: return EscapeSequences.cmdF[5]
        case .f7: return EscapeSequences.cmdF[6]
        case .f8: return EscapeSequences.cmdF[7]
        case .f9: return EscapeSequences.cmdF[8]
        case .f10: return EscapeSequences.cmdF[9]
        case .ctrl, .meta, .tilde, .pipe, .slash, .dash, .hideKeyboard: return nil
        }
    }

    /// Text this key types (goes through insertText so ctrl/meta apply).
    var insertedText: String? {
        switch self {
        case .tilde: return "~"
        case .pipe: return "|"
        case .slash: return "/"
        case .dash: return "-"
        default: return nil
        }
    }
}

/// Persists the user's key bar layout in UserDefaults.
enum KeyBarConfig {
    static let changedNotification = Notification.Name("pockterm.keyBarConfigChanged")
    private static let defaultsKey = "keyBarKeys"

    static let defaultKeys: [KeyBarKey] = [
        .esc, .ctrl, .meta, .tab, .tilde, .pipe, .slash, .dash,
        .left, .down, .up, .right, .pageUp, .pageDown, .f1, .hideKeyboard,
    ]

    static func load() -> [KeyBarKey] {
        guard let raw = UserDefaults.standard.stringArray(forKey: defaultsKey) else {
            return defaultKeys
        }
        let keys = raw.compactMap(KeyBarKey.init(rawValue:))
        return keys.isEmpty ? defaultKeys : keys
    }

    static func save(_ keys: [KeyBarKey]) {
        UserDefaults.standard.set(keys.map(\.rawValue), forKey: defaultsKey)
        NotificationCenter.default.post(name: changedNotification, object: nil)
    }
}
