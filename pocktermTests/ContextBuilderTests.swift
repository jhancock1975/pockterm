import Testing
@testable import pockterm

@Test func includesTerminalTextAndAttachmentsWhenUnderBudget() {
    let prompt = ContextBuilder.systemPrompt(
        terminalText: "$ ls\nfoo.txt",
        attachments: [ContextAttachment(name: "notes.md", contents: "remember the milk")],
        maxChars: 10_000)
    #expect(prompt.count <= 10_000)
    #expect(prompt.contains("$ ls\nfoo.txt"))
    #expect(prompt.contains("notes.md"))
    #expect(prompt.contains("remember the milk"))
}

@Test func keepsTheTailOfOversizedTerminalOutput() {
    let terminal = "OLDMARKER" + String(repeating: "x", count: 4_000) + "ERROR: db down"
    let prompt = ContextBuilder.systemPrompt(terminalText: terminal, attachments: [], maxChars: 600)
    #expect(prompt.count <= 600)
    #expect(prompt.contains("ERROR: db down"))
    #expect(!prompt.contains("OLDMARKER"))
}

@Test func truncatesOldestAttachmentFirstWhenOverBudget() {
    let oldest = ContextAttachment(name: "first.txt", contents: String(repeating: "a", count: 300))
    let newest = ContextAttachment(name: "second.txt", contents: String(repeating: "b", count: 300))
    let prompt = ContextBuilder.systemPrompt(
        terminalText: "", attachments: [oldest, newest], maxChars: 700)
    #expect(prompt.count <= 700)
    #expect(prompt.contains(String(repeating: "b", count: 300)))
    #expect(!prompt.contains(String(repeating: "a", count: 300)))
}

@Test func isDeterministic() {
    let attachments = [ContextAttachment(name: "a.txt", contents: String(repeating: "a", count: 500))]
    let first = ContextBuilder.systemPrompt(terminalText: "hello", attachments: attachments, maxChars: 400)
    let second = ContextBuilder.systemPrompt(terminalText: "hello", attachments: attachments, maxChars: 400)
    #expect(first == second)
}

@Test func neverExceedsATinyBudget() {
    let prompt = ContextBuilder.systemPrompt(
        terminalText: String(repeating: "t", count: 100),
        attachments: [ContextAttachment(name: "f", contents: "c")],
        maxChars: 50)
    #expect(prompt.count <= 50)
}
