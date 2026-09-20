import Testing
import SwiftTerm
@testable import pockterm

@Test @MainActor func steadyKeepsTheShapeAndDropsTheBlink() {
    #expect(CursorStyle.blinkBlock.steady == .steadyBlock)
    #expect(CursorStyle.blinkUnderline.steady == .steadyUnderline)
    #expect(CursorStyle.blinkBar.steady == .steadyBar)
}

@Test @MainActor func steadyLeavesAnAlreadySteadyCaretAlone() {
    #expect(CursorStyle.steadyBlock.steady == .steadyBlock)
    #expect(CursorStyle.steadyUnderline.steady == .steadyUnderline)
    #expect(CursorStyle.steadyBar.steady == .steadyBar)
}

@Test @MainActor func everyCursorStyleHasASteadyForm() {
    // A new case in SwiftTerm must not silently fall through to blinking.
    for style in CursorStyle.allCases {
        #expect(style.steady.steady == style.steady)
        #expect([CursorStyle.steadyBlock, .steadyUnderline, .steadyBar].contains(style.steady))
    }
}

@Test @MainActor func onlyALiveSessionTakesInput() {
    #expect(TerminalSession.Status.connecting.acceptsInput)
    #expect(TerminalSession.Status.connected.acceptsInput)
    #expect(!TerminalSession.Status.closed.acceptsInput)
    #expect(!TerminalSession.Status.idleDisconnected.acceptsInput)
    #expect(!TerminalSession.Status.failed("nope").acceptsInput)
}
