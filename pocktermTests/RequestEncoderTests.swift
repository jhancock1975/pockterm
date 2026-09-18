import Testing
@testable import pockterm

private let sample = ChatRequest(
    model: "M", system: "CTX",
    messages: [ChatMessage(role: .user, text: "hi")], maxTokens: 100)

@Test @MainActor func anthropicBodyPlacesSystemTopLevel() {
    let body = RequestEncoder.body(for: sample, provider: .anthropic)
    #expect(body["system"] as? String == "CTX")
    #expect(body["model"] as? String == "M")
    #expect(body["stream"] as? Bool == true)
    #expect(body["max_tokens"] as? Int == 100)
    let messages = body["messages"] as? [[String: Any]]
    #expect(messages?.count == 1)
    #expect(messages?.first?["role"] as? String == "user")
    #expect(messages?.allSatisfy { $0["role"] as? String != "system" } == true)
}

@Test @MainActor func openAIBodyLeadsWithSystemMessage() {
    let body = RequestEncoder.body(for: sample, provider: .openai)
    #expect(body["stream"] as? Bool == true)
    #expect(body["system"] == nil)
    let messages = body["messages"] as? [[String: Any]]
    #expect(messages?.count == 2)
    #expect(messages?.first?["role"] as? String == "system")
    #expect(messages?.first?["content"] as? String == "CTX")
    #expect(messages?.last?["role"] as? String == "user")
}

@Test @MainActor func openAIBodyUsesMaxCompletionTokens() {
    // OpenAI deprecated max_tokens on Chat Completions; gpt-5/o-series 400 on it.
    let body = RequestEncoder.body(for: sample, provider: .openai)
    #expect(body["max_completion_tokens"] as? Int == 100)
    #expect(body["max_tokens"] == nil)
}

@Test @MainActor func openRouterBodyKeepsMaxTokens() {
    // OpenRouter's normalized schema still takes max_tokens.
    let body = RequestEncoder.body(for: sample, provider: .openRouter)
    #expect(body["max_tokens"] as? Int == 100)
    #expect(body["max_completion_tokens"] == nil)
}

@Test @MainActor func huggingFaceUsesOpenAIWireFormatWithMaxTokens() {
    let body = RequestEncoder.body(for: sample, provider: .huggingFace)
    #expect(body["max_tokens"] as? Int == 100)
    #expect(body["max_completion_tokens"] == nil)
    let messages = body["messages"] as? [[String: Any]]
    #expect(messages?.first?["role"] as? String == "system")
    #expect(RequestEncoder.headers(for: .huggingFace, apiKey: "K")["Authorization"] == "Bearer K")
}

private let toolSample: ChatRequest = {
    var request = ChatRequest(
        model: "M", system: nil,
        messages: [
            ChatMessage(role: .user, text: "list files"),
            ChatMessage(role: .assistant, text: "",
                        toolCalls: [ToolCall(id: "c1", name: "run_command",
                                             argumentsJSON: #"{"command":"ls"}"#)]),
            ChatMessage(role: .tool, text: "file.txt", toolCallID: "c1"),
        ])
    request.tools = [ToolSpec(name: "run_command", description: "Run a shell command",
                              parameters: ["type": "object",
                                           "properties": ["command": ["type": "string"]],
                                           "required": ["command"]])]
    return request
}()

@Test @MainActor func openAIEncodesToolsAndToolTurns() {
    let body = RequestEncoder.body(for: toolSample, provider: .openai)
    let tools = body["tools"] as? [[String: Any]]
    #expect(tools?.first?["type"] as? String == "function")
    let function = tools?.first?["function"] as? [String: Any]
    #expect(function?["name"] as? String == "run_command")

    let messages = body["messages"] as? [[String: Any]]
    let assistant = messages?[1]
    let calls = assistant?["tool_calls"] as? [[String: Any]]
    #expect(calls?.first?["id"] as? String == "c1")
    #expect((calls?.first?["function"] as? [String: Any])?["arguments"] as? String
            == #"{"command":"ls"}"#)
    let toolMsg = messages?[2]
    #expect(toolMsg?["role"] as? String == "tool")
    #expect(toolMsg?["tool_call_id"] as? String == "c1")
    #expect(toolMsg?["content"] as? String == "file.txt")
}

@Test @MainActor func anthropicEncodesToolsAndToolTurns() {
    let body = RequestEncoder.body(for: toolSample, provider: .anthropic)
    let tools = body["tools"] as? [[String: Any]]
    #expect(tools?.first?["name"] as? String == "run_command")
    #expect(tools?.first?["input_schema"] != nil)

    let messages = body["messages"] as? [[String: Any]]
    let assistantBlocks = messages?[1]["content"] as? [[String: Any]]
    let toolUse = assistantBlocks?.first { $0["type"] as? String == "tool_use" }
    #expect(toolUse?["id"] as? String == "c1")
    #expect((toolUse?["input"] as? [String: Any])?["command"] as? String == "ls")

    let resultMsg = messages?[2]
    #expect(resultMsg?["role"] as? String == "user")
    let resultBlocks = resultMsg?["content"] as? [[String: Any]]
    #expect(resultBlocks?.first?["type"] as? String == "tool_result")
    #expect(resultBlocks?.first?["tool_use_id"] as? String == "c1")
    #expect(resultBlocks?.first?["content"] as? String == "file.txt")
}

@Test @MainActor func headersCarryKeyInProviderField() {
    #expect(RequestEncoder.headers(for: .anthropic, apiKey: "K")["x-api-key"] == "K")
    #expect(RequestEncoder.headers(for: .anthropic, apiKey: "K")["anthropic-version"] == "2023-06-01")
    #expect(RequestEncoder.headers(for: .openai, apiKey: "K")["Authorization"] == "Bearer K")
    #expect(RequestEncoder.headers(for: .openRouter, apiKey: "K")["Authorization"] == "Bearer K")
}
