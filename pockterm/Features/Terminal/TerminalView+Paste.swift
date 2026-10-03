import SwiftTerm

extension TerminalView {
    /// Sends `text` the way SwiftTerm's own paste(_:) sends the clipboard:
    /// wrapped in bracketed-paste markers when the program asked for them
    /// (zsh, bash and vim do), so a pasted line break doesn't run a command
    /// halfway through the paste. For text that arrives some other way, like
    /// glasses mode's Paste button, which gets it from the system's
    /// PasteButton without a permission prompt.
    func paste(text: String) {
        // ESC [ 200 ~ and ESC [ 201 ~. SwiftTerm's own copies are mutable
        // statics, which strict concurrency won't read.
        let bracketed = getTerminal().bracketedPasteMode
        if bracketed { send(data: Array("\u{1b}[200~".utf8)[...]) }
        send(txt: text)
        if bracketed { send(data: Array("\u{1b}[201~".utf8)[...]) }
    }
}
