import SwiftUI
import UIKit

// Right-to-left policy.
//
// When the UI language is Hebrew or Arabic, iOS mirrors the whole interface:
// navigation bars, lists, tab bars and stacks all flip. That is correct for
// chrome, and Pockterm lets it happen.
//
// It is wrong for terminal content, and every established terminal emulator
// agrees — xterm, iTerm2, GNOME Terminal and Windows Terminal all render the
// cell grid left-to-right no matter what the UI language is. The reason is
// structural rather than aesthetic: a terminal is a matrix of character cells
// addressed by column number, and the escape sequences the server sends
// ("move to column 40", "erase to end of line") count columns from the left.
// Mirroring the grid would put column 0 on the right and leave every
// cursor-addressed program — vim, htop, tmux — drawing its interface
// backwards. The server has no idea the client is running in Arabic.
//
// The same holds for technical input: a hostname, port, file path, octal
// permission mask or shell command is LTR content even when the surrounding
// UI is RTL. Typing `/var/log/syslog` into a mirrored field puts the leading
// slash on the right, which is both wrong and confusing to proof-read.
//
// Note this is about *layout direction*, not about bidirectional text. If a
// server sends Arabic or Hebrew text, the terminal displays whatever the
// server put in those cells; Pockterm does not attempt bidi reordering inside
// the grid, which is also the norm for terminal emulators.

extension View {
    /// Pins content left-to-right regardless of the UI language.
    ///
    /// Use for the terminal grid, the accessory key bar (whose arrow keys must
    /// keep pointing where they send), and fields holding technical values —
    /// hostnames, ports, paths, permissions and shell commands.
    ///
    /// Do **not** use it on ordinary prose or chrome: those should mirror.
    func forcesLeftToRight() -> some View {
        environment(\.layoutDirection, .leftToRight)
    }
}

extension UIView {
    /// UIKit counterpart of `forcesLeftToRight()`, applied to a view and all of
    /// its descendants.
    ///
    /// `TerminalHostView` needs this rather than the SwiftUI environment value:
    /// the SwiftTerm view is UIKit, so it resolves `leading`/`trailing`
    /// constraints and its own drawing against `semanticContentAttribute`,
    /// which the SwiftUI environment does not reach.
    func pinLeftToRightForTerminalContent() {
        semanticContentAttribute = .forceLeftToRight
        for subview in subviews {
            subview.pinLeftToRightForTerminalContent()
        }
    }
}
