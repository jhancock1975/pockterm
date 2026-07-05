import Testing
@testable import pockterm

@Test func anthropicDecodesTextDeltasOnly() {
    let d = StreamDecoder(provider: .anthropic)
    let delta = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#
    #expect(d.text(from: delta) == "Hello")
    #expect(d.text(from: "event: content_block_delta") == nil)
    #expect(d.text(from: #"data: {"type":"message_stop"}"#) == nil)
}

@Test func openAIDecodesContentAndIgnoresDone() {
    let d = StreamDecoder(provider: .openai)
    #expect(d.text(from: #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#) == "Hi")
    #expect(d.text(from: "data: [DONE]") == nil)
    #expect(d.text(from: "") == nil)
}

@Test func concatenatesAStream() {
    let d = StreamDecoder(provider: .openai)
    let lines = [
        #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#,
        #"data: {"choices":[{"delta":{"content":"lo"}}]}"#,
        "data: [DONE]",
    ]
    #expect(lines.compactMap { d.text(from: $0) }.joined() == "Hello")
}
