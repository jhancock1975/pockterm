import UIKit

/// A curated monospaced font the terminal can use. `id` is the exact
/// `UIFont(name:)` PostScript/family name; `name` is the display label.
/// Nothing is bundled — the list is filtered at runtime to fonts iOS actually
/// provides via `available()`.
struct TerminalFont: Identifiable {
    let id: String
    let name: String

    static let all: [TerminalFont] = [
        TerminalFont(id: "system", name: "System"),
        TerminalFont(id: "Menlo-Regular", name: "Menlo"),
        TerminalFont(id: "SFMono-Regular", name: "SF Mono"),
        TerminalFont(id: "CourierNewPSMT", name: "Courier New"),
        TerminalFont(id: "Courier", name: "Courier"),
    ]

    static func available() -> [TerminalFont] {
        all.filter { $0.id == "system" || UIFont(name: $0.id, size: 12) != nil }
    }

    static func font(id: String) -> TerminalFont {
        all.first { $0.id == id } ?? all[0]
    }
}
