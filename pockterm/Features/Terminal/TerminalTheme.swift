import SwiftTerm
import UIKit

/// A curated terminal color scheme. Pure value type — no UIKit/SwiftData
/// coupling — so it is fully unit-testable. `ansi` is the 16 ANSI colors in
/// SwiftTerm's expected order (0-7 normal, 8-15 bright).
struct TerminalTheme: Identifiable {
    let id: String
    let name: String
    let ansi: [Color]
    let foreground: Color
    let background: Color
    let cursor: Color

    private static func c(_ hex: UInt32) -> Color {
        Color(red: UInt16((hex >> 16) & 0xff) * 257,
              green: UInt16((hex >> 8) & 0xff) * 257,
              blue: UInt16(hex & 0xff) * 257)
    }

    private static func theme(_ id: String, _ name: String,
                              ansi: [UInt32], fg: UInt32, bg: UInt32, cursor: UInt32) -> TerminalTheme {
        TerminalTheme(id: id, name: name, ansi: ansi.map(c),
                      foreground: c(fg), background: c(bg), cursor: c(cursor))
    }

    static let all: [TerminalTheme] = [
        theme("default", "Default", ansi: [
            0x000000, 0xcd0000, 0x00cd00, 0xcdcd00, 0x0000ee, 0xcd00cd, 0x00cdcd, 0xe5e5e5,
            0x7f7f7f, 0xff0000, 0x00ff00, 0xffff00, 0x5c5cff, 0xff00ff, 0x00ffff, 0xffffff],
            fg: 0xe5e5e5, bg: 0x000000, cursor: 0xe5e5e5),
        theme("solarized-dark", "Solarized Dark", ansi: [
            0x073642, 0xdc322f, 0x859900, 0xb58900, 0x268bd2, 0xd33682, 0x2aa198, 0xeee8d5,
            0x002b36, 0xcb4b16, 0x586e75, 0x657b83, 0x839496, 0x6c71c4, 0x93a1a1, 0xfdf6e3],
            fg: 0x839496, bg: 0x002b36, cursor: 0x839496),
        theme("solarized-light", "Solarized Light", ansi: [
            0xeee8d5, 0xdc322f, 0x859900, 0xb58900, 0x268bd2, 0xd33682, 0x2aa198, 0x073642,
            0xfdf6e3, 0xcb4b16, 0x93a1a1, 0x839496, 0x657b83, 0x6c71c4, 0x586e75, 0x002b36],
            fg: 0x657b83, bg: 0xfdf6e3, cursor: 0x657b83),
        theme("nord", "Nord", ansi: [
            0x3b4252, 0xbf616a, 0xa3be8c, 0xebcb8b, 0x81a1c1, 0xb48ead, 0x88c0d0, 0xe5e9f0,
            0x4c566a, 0xbf616a, 0xa3be8c, 0xebcb8b, 0x81a1c1, 0xb48ead, 0x8fbcbb, 0xeceff4],
            fg: 0xd8dee9, bg: 0x2e3440, cursor: 0xd8dee9),
        theme("dracula", "Dracula", ansi: [
            0x21222c, 0xff5555, 0x50fa7b, 0xf1fa8c, 0xbd93f9, 0xff79c6, 0x8be9fd, 0xf8f8f2,
            0x6272a4, 0xff6e6e, 0x69ff94, 0xffffa5, 0xd6acff, 0xff92df, 0xa4ffff, 0xffffff],
            fg: 0xf8f8f2, bg: 0x282a36, cursor: 0xf8f8f2),
        theme("light", "Light", ansi: [
            0x000000, 0xc91b00, 0x00c200, 0xc7c400, 0x0225c7, 0xc930c7, 0x00c5c7, 0xc7c7c7,
            0x686868, 0xff6e67, 0x5ffa68, 0xfffc67, 0x6871ff, 0xff77ff, 0x60fdff, 0xffffff],
            fg: 0x000000, bg: 0xffffff, cursor: 0x000000),
    ]

    static func theme(id: String) -> TerminalTheme {
        all.first { $0.id == id } ?? all[0]
    }
}

extension TerminalTheme {
    /// Converts a SwiftTerm 16-bit `Color` to a `UIColor`.
    static func uiColor(_ c: Color) -> UIColor {
        UIColor(red: CGFloat(c.red) / 65535, green: CGFloat(c.green) / 65535,
                blue: CGFloat(c.blue) / 65535, alpha: 1)
    }
}
