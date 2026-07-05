import Testing
@testable import pockterm

private let sample = ChatRequest(
    model: "M", system: "CTX",
    messages: [ChatMessage(role: .user, text: "hi")], maxTokens: 100)

@Test func anthropicBodyPlacesSystemTopLevel() {
    let body = RequestEncoder.body(for: sample, provider: .anthropic)
    #expect(body["system"] as? String == "CTX")
    #expect(body["model"] as? String == "M")
    #expect(body["stream"] as? Bool == true)
    #expect(body["max_tokens"] as? Int == 100)
    let messages = body["messages"] as? [[String: String]]
    #expect(messages?.count == 1)
    #expect(messages?.first?["role"] == "user")
    #expect(messages?.allSatisfy { $0["role"] != "system" } == true)
}

@Test func openAIBodyLeadsWithSystemMessage() {
    let body = RequestEncoder.body(for: sample, provider: .openai)
    #expect(body["stream"] as? Bool == true)
    #expect(body["system"] == nil)
    let messages = body["messages"] as? [[String: String]]
    #expect(messages?.count == 2)
    #expect(messages?.first?["role"] == "system")
    #expect(messages?.first?["content"] == "CTX")
    #expect(messages?.last?["role"] == "user")
}

@Test func headersCarryKeyInProviderField() {
    #expect(RequestEncoder.headers(for: .anthropic, apiKey: "K")["x-api-key"] == "K")
    #expect(RequestEncoder.headers(for: .anthropic, apiKey: "K")["anthropic-version"] == "2023-06-01")
    #expect(RequestEncoder.headers(for: .openai, apiKey: "K")["Authorization"] == "Bearer K")
    #expect(RequestEncoder.headers(for: .openRouter, apiKey: "K")["Authorization"] == "Bearer K")
}
