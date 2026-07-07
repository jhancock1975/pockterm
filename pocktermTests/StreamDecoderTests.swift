import Testing
@testable import pockterm

@Test func anthropicDecodesTextDeltasOnly() {
    let d = StreamDecoder(provider: .anthropic)
    let delta = #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hello"}}"#
    #expect(d.events(from: delta) == [.text("Hello")])
    #expect(d.events(from: "event: content_block_delta") == [])
    #expect(d.events(from: #"data: {"type":"message_stop"}"#) == [])
}

@Test func openAIDecodesContentAndIgnoresDone() {
    let d = StreamDecoder(provider: .openai)
    #expect(d.events(from: #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#) == [.text("Hi")])
    #expect(d.events(from: "data: [DONE]") == [])
    #expect(d.events(from: "") == [])
}

@Test func concatenatesAStream() {
    let d = StreamDecoder(provider: .openai)
    let lines = [
        #"data: {"choices":[{"delta":{"content":"Hel"}}]}"#,
        #"data: {"choices":[{"delta":{"content":"lo"}}]}"#,
        "data: [DONE]",
    ]
    let text = lines.flatMap { d.events(from: $0) }.compactMap { event -> String? in
        if case .text(let t) = event { return t }
        return nil
    }.joined()
    #expect(text == "Hello")
}

@Test func openAIAssemblesStreamedToolCallFragments() {
    let decoder = StreamDecoder(provider: .openai)
    var events: [AIStreamEvent] = []
    let lines = [
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"run_command","arguments":""}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"comm"}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"and\":\"ls\"}"}}]}}]}"#,
        #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
        "data: [DONE]",
    ]
    for line in lines { events += decoder.events(from: line) }
    events += decoder.finish()
    #expect(events == [.toolCall(ToolCall(id: "c1", name: "run_command",
                                          argumentsJSON: #"{"command":"ls"}"#))])
}

@Test func anthropicAssemblesToolUseBlocks() {
    let decoder = StreamDecoder(provider: .anthropic)
    var events: [AIStreamEvent] = []
    let lines = [
        #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"c9","name":"read_file"}}"#,
        #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"path\":"}}"#,
        #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"/etc/hosts\"}"}}"#,
        #"data: {"type":"content_block_stop","index":1}"#,
    ]
    for line in lines { events += decoder.events(from: line) }
    #expect(events == [.toolCall(ToolCall(id: "c9", name: "read_file",
                                          argumentsJSON: #"{"path":"/etc/hosts"}"#))])
}

@Test func textDeltasStillFlowAsEvents() {
    let decoder = StreamDecoder(provider: .openai)
    let line = #"data: {"choices":[{"delta":{"content":"hi"}}]}"#
    #expect(decoder.events(from: line) == [.text("hi")])
}
