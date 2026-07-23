import Testing
import UIKit
@testable import pockterm

@Test func menloIsTheDefaultFont() {
    #expect(TerminalFont.all.first?.id == "Menlo-Regular")
    #expect(TerminalFont.font(id: "Menlo-Regular").name == "Menlo")
}

@Test func unknownFontIdFallsBackToMenlo() {
    #expect(TerminalFont.font(id: "Comic Sans").id == "Menlo-Regular")
}

@Test func availableFontsAreAllInstantiableAndNonEmpty() {
    let avail = TerminalFont.available()
    #expect(!avail.isEmpty)
    for f in avail {
        #expect(UIFont(name: f.id, size: 12) != nil, "\(f.id) should instantiate")
    }
    // Menlo ships on every iOS, so it must survive the filter.
    #expect(avail.contains { $0.id == "Menlo-Regular" })
}
