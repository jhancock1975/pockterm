import Testing
import Foundation
@testable import pockterm

@MainActor
@Test func parsesProviderModelListJSON() {
    let openAIShape = #"{"object":"list","data":[{"id":"gpt-4o","object":"model"},{"id":"gpt-4o-mini","object":"model"}]}"#
    #expect(ModelCatalog.parseModels(Data(openAIShape.utf8), provider: .openai) == ["gpt-4o", "gpt-4o-mini"])

    let anthropicShape = #"{"data":[{"type":"model","id":"claude-opus-4-8"},{"type":"model","id":"claude-haiku-4-5"}],"has_more":false}"#
    #expect(ModelCatalog.parseModels(Data(anthropicShape.utf8), provider: .anthropic) == ["claude-haiku-4-5", "claude-opus-4-8"])
}

@MainActor
@Test func parseToleratesGarbage() {
    #expect(ModelCatalog.parseModels(Data("not json".utf8), provider: .anthropic) == [])
    #expect(ModelCatalog.parseModels(Data(#"{"data":"nope"}"#.utf8), provider: .anthropic) == [])
    #expect(ModelCatalog.parseModels(Data(#"{"data":[{"name":"no id"}]}"#.utf8), provider: .anthropic) == [])
}

@Test @MainActor func openRouterFilterKeepsTextOutputModels() {
    let json = """
    {"data":[
      {"id":"a/text","architecture":{"modality":"text->text"}},
      {"id":"b/vision","architecture":{"modality":"text+image->text"}},
      {"id":"c/image-gen","architecture":{"modality":"text->image"}},
      {"id":"d/no-arch"}
    ]}
    """.data(using: .utf8)!
    #expect(ModelCatalog.parseModels(json, provider: .openRouter)
            == ["a/text", "b/vision", "d/no-arch"])
}

@Test @MainActor func openAIFilterDropsNonChatFamilies() {
    let json = """
    {"data":[{"id":"gpt-5"},{"id":"whisper-1"},{"id":"tts-1"},{"id":"dall-e-3"},
             {"id":"text-embedding-3-small"},{"id":"omni-moderation-latest"},
             {"id":"gpt-4o-realtime-preview"},{"id":"gpt-4o"}]}
    """.data(using: .utf8)!
    #expect(ModelCatalog.parseModels(json, provider: .openai) == ["gpt-4o", "gpt-5"])
}

@Test @MainActor func anthropicAndHFPassThrough() {
    let json = #"{"data":[{"id":"m2"},{"id":"m1"}]}"#.data(using: .utf8)!
    #expect(ModelCatalog.parseModels(json, provider: .anthropic) == ["m1", "m2"])
    #expect(ModelCatalog.parseModels(json, provider: .huggingFace) == ["m1", "m2"])
}

@Test @MainActor func storeIgnoresEmptyListAndStampsTime() {
    let provider = AIProvider.anthropic
    UserDefaults.standard.removeObject(forKey: "modelCatalog.\(provider.rawValue)")
    UserDefaults.standard.removeObject(forKey: "modelCatalog.lastRefreshed.\(provider.rawValue)")
    ModelCatalog.storeModels(["m1"], for: provider)
    #expect(ModelCatalog.cachedModels(for: provider) == ["m1"])
    #expect(ModelCatalog.lastRefreshed(for: provider) != nil)
    ModelCatalog.storeModels([], for: provider)          // failure-shaped result
    #expect(ModelCatalog.cachedModels(for: provider) == ["m1"])  // last known good kept
}

@Test @MainActor func emptyCacheSeedsDefaultModel() {
    UserDefaults.standard.removeObject(forKey: "modelCatalog.huggingFace")
    let catalog = ModelCatalog(provider: .huggingFace, apiKey: nil)
    #expect(catalog.visibleModels == [AIProvider.huggingFace.defaultModel])
}

@Test func keyStoreTrimsPastedWhitespace() throws {
    let store = AIKeyStore(secretStore: InMemorySecretStore())
    try store.setKey("sk-test-abc\n", for: .openai)
    #expect(try store.key(for: .openai) == "sk-test-abc")
}
