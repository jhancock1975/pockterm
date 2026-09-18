import Testing
@testable import pockterm

private func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }

@Test @MainActor func tracksPrintableAndReturnsLineOnEnter() {
    var t = TypedLineTracker()
    #expect(t.consume(bytes("git status")) == nil)
    #expect(t.line == "git status")
    #expect(t.consume([0x0d]) == "git status")   // Enter
    #expect(t.line == "")                         // reset
}

@Test @MainActor func backspaceRemovesLastCharacter() {
    var t = TypedLineTracker()
    _ = t.consume(bytes("gitx"))
    _ = t.consume([0x7f])                          // Backspace
    #expect(t.line == "git")
}

@Test @MainActor func bareEnterReturnsNil() {
    var t = TypedLineTracker()
    #expect(t.consume([0x0a]) == nil)              // newline, empty line
    #expect(t.line == "")
}

@Test @MainActor func controlSequenceResetsLine() {
    var t = TypedLineTracker()
    _ = t.consume(bytes("ls -la"))
    _ = t.consume([0x1b, 0x5b, 0x41])              // ESC [ A  (up arrow)
    #expect(t.line == "")
}
