import Foundation

/// A file the user attached to the conversation, already read into text.
/// (Named to avoid colliding with Swift Testing's `Attachment`.)
struct ContextAttachment: Identifiable {
    let id = UUID()
    let name: String
    let contents: String
}

/// Assembles the assistant's system prompt from terminal output and attached
/// files, deterministically capped at `maxChars`.
enum ContextBuilder {
    private static let preamble = """
    You are a terminal assistant inside an SSH client on iPhone. Use the \
    terminal output and attached files below to answer questions and suggest \
    shell commands. When you suggest a command to run, put it alone in a \
    fenced code block so the app can offer to run it.
    """

    /// Builds the system prompt: preamble, then the tail of the terminal
    /// output, then attachments. When over budget the terminal tail wins,
    /// then newer attachments; older attachments are truncated or dropped.
    static func systemPrompt(terminalText: String, attachments: [ContextAttachment],
                             maxChars: Int) -> String {
        var result = String(preamble.prefix(max(maxChars, 0)))
        var remaining = maxChars - result.count

        let terminalHeader = "\n\n[Terminal output — most recent last]\n"
        if !terminalText.isEmpty, remaining > terminalHeader.count {
            let body = String(terminalText.suffix(remaining - terminalHeader.count))
            result += terminalHeader + body
            remaining -= terminalHeader.count + body.count
        }

        // Fill newest-first so older attachments lose out, but keep the
        // original order in the assembled prompt.
        var kept: [(index: Int, section: String)] = []
        for (index, attachment) in attachments.enumerated().reversed() {
            let header = "\n\n[File: \(attachment.name)]\n"
            guard remaining > header.count else { break }
            let body = String(attachment.contents.prefix(remaining - header.count))
            kept.append((index, header + body))
            remaining -= header.count + body.count
        }
        for (_, section) in kept.sorted(by: { $0.index < $1.index }) {
            result += section
        }
        return result
    }
}
