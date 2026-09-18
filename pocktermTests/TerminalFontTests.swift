import Testing
import UIKit
@testable import pockterm

@Test @MainActor func systemIsTheDefaultFont() {
    #expect(TerminalFont.all.first?.id == "system")
    #expect(TerminalFont.all.contains { $0.id == "Menlo-Regular" })
    #expect(TerminalFont.font(id: "Menlo-Regular").name == "Menlo")
}

@Test @MainActor func unknownFontIdFallsBackToSystem() {
    #expect(TerminalFont.font(id: "Comic Sans").id == "system")
}

@Test @MainActor func availableFontsAreAllInstantiableAndNonEmpty() {
    let avail = TerminalFont.available()
    #expect(!avail.isEmpty)
    #expect(avail.contains { $0.id == "system" })
    // Menlo ships on every iOS, so it must survive the filter.
    #expect(avail.contains { $0.id == "Menlo-Regular" })
    for f in avail where f.id != "system" {
        #expect(UIFont(name: f.id, size: 12) != nil, "\(f.id) should instantiate")
    }
}
