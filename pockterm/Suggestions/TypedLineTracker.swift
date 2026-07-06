import Foundation

/// Reconstructs the command line the user is typing from the raw keystroke bytes
/// sent to the shell. This is a heuristic — remote-side line editing (arrow-key
/// edits, Ctrl-R, multi-line input) can desync it, so any unrecognized control
/// byte conservatively clears the model. It re-syncs on the next Enter.
struct TypedLineTracker {
    private(set) var line: String = ""
    /// Set when a control byte arrives (e.g. the ESC of an arrow-key sequence);
    /// everything is ignored until the next Enter so the sequence's printable
    /// tail bytes ("[A") don't pollute the line.
    private var desynced = false

    /// Feeds outgoing bytes through the model. Returns the finished command line
    /// (trimmed, non-empty) when Enter is seen, otherwise nil.
    mutating func consume(_ bytes: [UInt8]) -> String? {
        var finished: String?
        for byte in bytes {
            switch byte {
            case 0x0a, 0x0d:                       // LF / CR — Enter
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                line = ""
                if !trimmed.isEmpty, !desynced { finished = trimmed }
                desynced = false
            case _ where desynced:                 // mid-sequence — ignore
                continue
            case 0x7f, 0x08:                       // DEL / BS — Backspace
                if !line.isEmpty { line.removeLast() }
            case 0x20...0x7e:                      // printable ASCII
                line.append(Character(UnicodeScalar(byte)))
            default:                               // any other control byte
                line = ""
                desynced = true
            }
        }
        return finished
    }
}
