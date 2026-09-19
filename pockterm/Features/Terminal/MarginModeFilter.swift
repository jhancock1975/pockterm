import Foundation

/// Strips DECLRMM — DEC private mode 69, left/right margins — from the bytes a
/// server sends us, before they reach SwiftTerm.
///
/// **Why this exists.** SwiftTerm 1.20.0 corrupts the screen when Insert Line
/// or Delete Line runs while margin mode is on. Both walk the buffer starting
/// at the *cursor* row but count the *scroll region's full height*
/// (`Terminal.swift`, `cmdInsertLines` / `cmdDeleteLines`):
///
/// ```swift
/// let rowCount = buffer.scrollBottom - buffer.scrollTop   // region height
/// let src = buffer.lines [row+i+1]                        // row = cursor row
/// ```
///
/// With the cursor near the bottom that walks past the last line, and
/// `CircularList`'s subscript wraps modulo its backing array, so the tail of
/// the walk overwrites rows at the *top* of the screen. Measured against a
/// real `tmux` + `emacs` session: 14 rows disagreed with what tmux believed it
/// had drawn, the emacs menu bar was destroyed, and the mode line landed in
/// the wrong row — which is the "mode line gets corrupted inside tmux" report.
///
/// **Why filtering is enough.** tmux is the only thing that turns the mode on
/// (measured: emacs and vim alone never send it; tmux sends it six times at
/// startup even for a bare shell). It uses margins only as a redraw
/// optimisation and falls back to full repaints without them, so declining the
/// mode costs nothing visible — the same live session renders identically to
/// tmux's own `capture-pane` with this filter in place.
///
/// **Remove this** once a SwiftTerm release carries the upstream fix; the
/// filter is a stopgap, not the repair.
struct MarginModeFilter {
    /// A partial `ESC [ ? … ` sequence, held back until its final byte arrives.
    /// SSH hands us arbitrary chunks, so the sequence can straddle two reads.
    private var pending: [UInt8] = []

    /// How long we will hold an unterminated sequence before giving up and
    /// passing it through. Without this, a stream that opens a CSI and never
    /// closes it would stall the terminal.
    private static let maxPending = 64

    private static let escape: UInt8 = 0x1b
    private static let leftBracket: UInt8 = 0x5b
    private static let question: UInt8 = 0x3f
    private static let semicolon: UInt8 = 0x3b
    private static let setFinal: UInt8 = 0x68          // 'h'

    mutating func filter(_ incoming: some Collection<UInt8>) -> [UInt8] {
        var buf = pending
        pending = []
        buf.append(contentsOf: incoming)

        var out: [UInt8] = []
        out.reserveCapacity(buf.count)

        var i = 0
        while i < buf.count {
            guard buf[i] == Self.escape else { out.append(buf[i]); i += 1; continue }

            // Only `ESC [ ? <params> h` is interesting. Anything else is
            // emitted a byte at a time and re-examined from the next byte,
            // which leaves every other sequence untouched.
            var j = i + 1
            guard j < buf.count else { pending = Array(buf[i...]); break }
            guard buf[j] == Self.leftBracket else { out.append(buf[i]); i += 1; continue }
            j += 1
            guard j < buf.count else { pending = Array(buf[i...]); break }
            guard buf[j] == Self.question else { out.append(buf[i]); i += 1; continue }
            j += 1

            let paramStart = j
            while j < buf.count, (buf[j] >= 0x30 && buf[j] <= 0x39) || buf[j] == Self.semicolon {
                j += 1
            }
            guard j < buf.count else {
                if buf.count - i > Self.maxPending {
                    out.append(contentsOf: buf[i...])
                    i = buf.count
                } else {
                    pending = Array(buf[i...])
                }
                break
            }

            guard buf[j] == Self.setFinal else {
                out.append(contentsOf: buf[i...j]); i = j + 1; continue
            }

            let params = String(decoding: buf[paramStart..<j], as: UTF8.self)
                .split(separator: ";", omittingEmptySubsequences: false)
                .map(String.init)
            let kept = params.filter { $0 != "69" }
            if kept.count == params.count {
                out.append(contentsOf: buf[i...j])              // nothing to strip
            } else if kept.contains(where: { !$0.isEmpty }) {
                // 69 travelled with other modes: keep them, drop only 69.
                out.append(contentsOf: Array("\u{1b}[?\(kept.joined(separator: ";"))h".utf8))
            }
            // else: 69 was the whole sequence, so it disappears entirely.
            i = j + 1
        }
        return out
    }
}
