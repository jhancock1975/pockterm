import Foundation

/// Reconstructs the command line the user is typing from the raw keystroke bytes
/// sent to the shell. This is a heuristic — remote-side line editing (arrow-key
/// edits, Ctrl-R, multi-line input) can desync it, so any unrecognized control
/// byte conservatively clears the model. It re-syncs on the next Enter.
struct TypedLineTracker {
    private(set) var line: String = ""

    /// Feeds outgoing bytes through the model. Returns the finished command line
    /// (trimmed, non-empty) when Enter is seen, otherwise nil.
    mutating func consume(_ bytes: [UInt8]) -> String? {
        var finished: String?
        for byte in bytes {
            switch byte {
            case 0x0a, 0x0d:                       // LF / CR — Enter
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                line = ""
                if !trimmed.isEmpty { finished = trimmed }
            case 0x7f, 0x08:                       // DEL / BS — Backspace
                if !line.isEmpty { line.removeLast() }
            case 0x20...0x7e:                      // printable ASCII
                line.append(Character(UnicodeScalar(byte)))
            default:                               // any other control byte
                line = ""
            }
        }
        return finished
    }
}
