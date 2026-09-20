import SwiftTerm

extension CursorStyle {
    /// The same caret shape with the blink taken off it.
    ///
    /// Shape is deliberately preserved: a server that asked for a bar caret
    /// through DECSCUSR should still get a bar when the session dies, just one
    /// that holds still.
    var steady: CursorStyle {
        switch self {
        case .blinkBlock, .steadyBlock: return .steadyBlock
        case .blinkUnderline, .steadyUnderline: return .steadyUnderline
        case .blinkBar, .steadyBar: return .steadyBar
        }
    }
}

extension TerminalSession.Status {
    /// Whether the far end can still take a keystroke.
    ///
    /// `connecting` counts: the caret belongs to a session that is on its way
    /// up, and stopping the blink for the second before the shell appears
    /// would only flicker.
    var acceptsInput: Bool {
        switch self {
        case .connecting, .connected: return true
        case .failed, .closed, .idleDisconnected: return false
        }
    }
}
