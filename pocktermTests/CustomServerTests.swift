import Testing
import Foundation
@testable import pockterm

@Test func bareAddressGetsHTTPAndV1() {
    let e = CustomServer.endpoints(from: "192.168.1.20:11434")
    #expect(e?.chat.absoluteString == "http://192.168.1.20:11434/v1/chat/completions")
    #expect(e?.models.absoluteString == "http://192.168.1.20:11434/v1/models")
}

@Test func addressesTypedEveryUsualWayLandOnTheSameEndpoints() {
    let want = "http://pc.local:8080/v1/chat/completions"
    for typed in ["pc.local:8080", "http://pc.local:8080", "http://pc.local:8080/",
                  "http://pc.local:8080/v1", "http://pc.local:8080/v1/",
                  "  http://pc.local:8080/v1/chat/completions \n",
                  "http://pc.local:8080/v1/models", "http://pc.local:8080/v1?x=1#y"] {
        #expect(CustomServer.endpoints(from: typed)?.chat.absoluteString == want, "\(typed)")
    }
}

@Test func httpsAndAPathPrefixAreKept() {
    let e = CustomServer.endpoints(from: "https://llm.example.com/ollama")
    #expect(e?.chat.absoluteString == "https://llm.example.com/ollama/v1/chat/completions")
}

@Test func nonAddressesAreRefused() {
    for typed in ["", "   ", "ftp://pc.local", "http://", "://x"] {
        #expect(CustomServer.endpoints(from: typed) == nil, "\(typed)")
    }
}

@Test func selfHostedNeedsNoKeyAndSendsNoEmptyBearer() {
    #expect(!AIProvider.custom.requiresAPIKey)
    #expect(AIProvider.custom.apiKeyHelpURL == nil)
    #expect(RequestEncoder.headers(for: .custom, apiKey: "")["Authorization"] == nil)
    #expect(RequestEncoder.headers(for: .custom, apiKey: "sk-1")["Authorization"] == "Bearer sk-1")
}

@Test func selfHostedSpeaksChatCompletions() {
    let request = ChatRequest(model: "qwen3:8b", system: "be brief",
                              messages: [ChatMessage(role: .user, text: "hi")], maxTokens: 16)
    let body = RequestEncoder.body(for: request, provider: .custom)
    #expect(body["max_tokens"] as? Int == 16)
    let messages = body["messages"] as? [[String: Any]]
    #expect(messages?.first?["role"] as? String == "system")
}

@Test func embeddingModelsAreLeftOutOfTheList() {
    let json = #"{"data":[{"id":"qwen3:8b"},{"id":"nomic-embed-text:latest"},{"id":"llama3.2"}]}"#
    #expect(ModelCatalog.parseModels(Data(json.utf8), provider: .custom) == ["llama3.2", "qwen3:8b"])
}
