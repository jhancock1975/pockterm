import Testing
@testable import pockterm

private func bytes(_ s: String) -> [UInt8] { Array(s.utf8) }
private func text(_ b: [UInt8]) -> String { String(decoding: b, as: UTF8.self) }

/// `ESC` written out, so the expectations below read as the sequences they are.
private let esc = "\u{1b}"

@Test func dropsAStandaloneMarginModeEnable() {
    var f = MarginModeFilter()
    #expect(text(f.filter(bytes("\(esc)[?69h"))) == "")
}

@Test func leavesOtherPrivateModesAlone() {
    var f = MarginModeFilter()
    let s = "\(esc)[?1049h\(esc)[?25l\(esc)[?2004h"
    #expect(text(f.filter(bytes(s))) == s)
}

@Test func leavesTheMarginModeResetAlone() {
    // We never enable the mode, so the reset is a no-op — pass it through
    // rather than second-guessing the server.
    var f = MarginModeFilter()
    #expect(text(f.filter(bytes("\(esc)[?69l"))) == "\(esc)[?69l")
}

@Test func removesOnlyTheMarginParameterFromACombinedEnable() {
    var f = MarginModeFilter()
    #expect(text(f.filter(bytes("\(esc)[?69;1049h"))) == "\(esc)[?1049h")
    #expect(text(f.filter(bytes("\(esc)[?1000;69;1002h"))) == "\(esc)[?1000;1002h")
}

@Test func doesNotTouchParametersThatMerelyContain69() {
    var f = MarginModeFilter()
    let s = "\(esc)[?690h\(esc)[?169h\(esc)[?6h"
    #expect(text(f.filter(bytes(s))) == s)
}

@Test func passesOrdinaryTextThrough() {
    var f = MarginModeFilter()
    let s = "hello world\r\n$ ls -la\r\n"
    #expect(text(f.filter(bytes(s))) == s)
}

@Test func joinsASequenceSplitAcrossChunks() {
    // SSH delivers arbitrary chunks, so the sequence can straddle two reads.
    for split in 1..<6 {
        var f = MarginModeFilter()
        let whole = bytes("A\(esc)[?69hB")
        let cut = 1 + split
        var out = f.filter(Array(whole[0..<cut])[...])
        out += f.filter(Array(whole[cut...])[...])
        #expect(text(out) == "AB", "split after \(cut) bytes")
    }
}

@Test func joinsACombinedSequenceSplitAcrossChunks() {
    var f = MarginModeFilter()
    var out = f.filter(bytes("\(esc)[?69;"))
    out += f.filter(bytes("1049h"))
    #expect(text(out) == "\(esc)[?1049h")
}

@Test func doesNotStallOnAnUnterminatedSequence() {
    // A long run of parameter bytes with no final byte must not be buffered
    // forever; it is released once it cannot plausibly be the sequence.
    var f = MarginModeFilter()
    let junk = "\(esc)[?" + String(repeating: "1;", count: 60)
    let out = f.filter(bytes(junk))
    #expect(!out.isEmpty)
}

@Test func handlesATrailingEscapeAtTheEndOfAChunk() {
    var f = MarginModeFilter()
    var out = f.filter(bytes("x\(esc)"))
    out += f.filter(bytes("[?69h"))
    #expect(text(out) == "x")
}

@Test func filtersTheRealTmuxPrelude() {
    // The bytes tmux actually sends on startup, from a captured session.
    var f = MarginModeFilter()
    let prelude = "\(esc)[?1049h\(esc)[22;0;0t\(esc)[?1h\(esc)=\(esc)[H\(esc)[2J"
        + "\(esc)[?69h\(esc)[1;46s\(esc)[?69h\(esc)[?12l\(esc)[?25h"
    let out = text(f.filter(bytes(prelude)))
    #expect(!out.contains("\(esc)[?69h"))
    #expect(out.contains("\(esc)[?1049h"))
    #expect(out.contains("\(esc)[2J"))
    #expect(out.contains("\(esc)[1;46s"))
}
