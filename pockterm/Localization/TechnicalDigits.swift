import Foundation

// Digit shape in technical values.
//
// SwiftUI's `Text("port \(somePort)")` builds a LocalizedStringKey, and an
// integer interpolated into one is formatted for the user's locale. In Arabic
// that renders 22 as ٢٢ (Arabic-Indic digits), and in several Indic locales it
// picks up that script's digits too.
//
// For a count — "3 sessions", "12 selected" — that is exactly right, and those
// call sites deliberately keep locale formatting.
//
// For an identifier it is wrong. A port, an octal permission mask or a
// hostname fragment has to match what the user typed into a config file on the
// server, and ٢٢ does not read as 22 when you are checking it against
// `sshd_config`. Every terminal client keeps these in Latin digits regardless
// of UI language, for the same reason the terminal grid stays left-to-right:
// the value belongs to the remote machine, not to the phone's locale.

nonisolated extension BinaryInteger {
    /// The value in Latin digits, never localized.
    ///
    /// Use when interpolating an identifier — a port, a permission mask — into
    /// a `Text`. Use plain interpolation for genuine counts, which should
    /// follow the user's locale.
    var technicalDigits: String { String(self, radix: 10) }
}

extension FormatStyle where Self == IntegerFormatStyle<Int> {
    /// Port-style formatting for an editable field: Latin digits, no grouping
    /// separator, whatever the UI language.
    ///
    /// `TextField(value:format: .number)` formats for the user's locale, which
    /// does to an editable port exactly what plain interpolation does to a
    /// displayed one — an Arabic user sees ٨٬٠٨٠ in a field they typed 8080
    /// into, complete with a thousands separator that is meaningless in a port.
    /// This is the `TextField` counterpart to `technicalDigits`.
    static var technicalPort: IntegerFormatStyle<Int> {
        IntegerFormatStyle<Int>(locale: Locale(identifier: "en_US_POSIX"))
            .grouping(.never)
    }
}
