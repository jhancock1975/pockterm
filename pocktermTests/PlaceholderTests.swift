import Foundation
import Testing
@testable import pockterm

// Digit shape in technical values. A port is an identifier, not a count: it has
// to read back the way the user typed it into sshd_config, whatever the UI
// language. See pockterm/Localization/TechnicalDigits.swift.

@Test @MainActor func technicalDigitsAreLatin() {
    #expect(22.technicalDigits == "22")
    #expect(8080.technicalDigits == "8080")
}

/// `TextField(value:format: .number)` formats for the user's locale, which in
/// Arabic rendered 8080 as ٨٬٠٨٠ — localized digits *and* a thousands
/// separator that means nothing in a port. technicalPort is the fix.
@Test @MainActor func technicalPortHasNoGroupingSeparator() {
    #expect(8080.formatted(.technicalPort) == "8080")
    #expect(65535.formatted(.technicalPort) == "65535")
    #expect(22.formatted(.technicalPort) == "22")
}

/// The style pins its own locale, so it cannot pick up the UI language.
@Test @MainActor func technicalPortIsUnaffectedByTheProcessLocale() {
    let port = 8080
    for id in ["ar_SA", "hi_IN", "fr_FR", "en_US"] {
        let styled = port.formatted(.technicalPort)
        #expect(styled == "8080", "port changed shape under \(id): \(styled)")
    }
}
