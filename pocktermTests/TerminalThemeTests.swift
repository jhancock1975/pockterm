import Testing
import SwiftTerm
@testable import pockterm

@Test func everyThemeHas16AnsiColors() {
    for theme in TerminalTheme.all {
        #expect(theme.ansi.count == 16, "\(theme.id) must have 16 ANSI colors")
    }
}

@Test func defaultThemeIsFirstAndBlack() {
    #expect(TerminalTheme.all.first?.id == "default")
    let def = TerminalTheme.theme(id: "default")
    #expect(def.background.red == 0 && def.background.green == 0 && def.background.blue == 0)
}

@Test func unknownThemeIdFallsBackToDefault() {
    #expect(TerminalTheme.theme(id: "nope").id == "default")
}

@Test func knownThemeIdLookupSucceeds() {
    #expect(TerminalTheme.theme(id: "dracula").id == "dracula")
    #expect(TerminalTheme.all.map(\.id).sorted()
            == ["default", "dracula", "light", "nord", "solarized-dark", "solarized-light"])
}
