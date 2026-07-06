import Testing
import Foundation
@testable import pockterm

@MainActor
@Test func parsesProviderModelListJSON() {
    let openAIShape = #"{"object":"list","data":[{"id":"gpt-4o","object":"model"},{"id":"gpt-4o-mini","object":"model"}]}"#
    #expect(ModelCatalog.parseModels(Data(openAIShape.utf8)) == ["gpt-4o", "gpt-4o-mini"])

    let anthropicShape = #"{"data":[{"type":"model","id":"claude-opus-4-8"},{"type":"model","id":"claude-haiku-4-5"}],"has_more":false}"#
    #expect(ModelCatalog.parseModels(Data(anthropicShape.utf8)) == ["claude-haiku-4-5", "claude-opus-4-8"])
}

@MainActor
@Test func parseToleratesGarbage() {
    #expect(ModelCatalog.parseModels(Data("not json".utf8)) == [])
    #expect(ModelCatalog.parseModels(Data(#"{"data":"nope"}"#.utf8)) == [])
    #expect(ModelCatalog.parseModels(Data(#"{"data":[{"name":"no id"}]}"#.utf8)) == [])
}

@Test func keyStoreTrimsPastedWhitespace() throws {
    let store = AIKeyStore(secretStore: InMemorySecretStore())
    try store.setKey("sk-test-abc\n", for: .openai)
    #expect(try store.key(for: .openai) == "sk-test-abc")
}
