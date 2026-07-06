import Testing
import Foundation
import SwiftData
@testable import pockterm

@Test func keyStoreRoundTripsPerProvider() throws {
    let store = AIKeyStore(secretStore: InMemorySecretStore())
    try store.setKey("sk-test-123", for: .anthropic)
    #expect(try store.key(for: .anthropic) == "sk-test-123")
    #expect(try store.key(for: .openai) == nil)

    try store.setKey("sk-other", for: .anthropic)
    #expect(try store.key(for: .anthropic) == "sk-other")

    try store.removeKey(for: .anthropic)
    #expect(try store.key(for: .anthropic) == nil)
}

@MainActor
@Test func aiSettingsPersists() throws {
    let container = try ModelContainer(
        for: AISettings.self, configurations: .init(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    ctx.insert(AISettings(provider: .openRouter, model: "openai/gpt-4o"))
    try ctx.save()

    let fetched = try ctx.fetch(FetchDescriptor<AISettings>())
    #expect(fetched.count == 1)
    #expect(fetched[0].activeProvider == .openRouter)
    #expect(fetched[0].model == "openai/gpt-4o")
}

@MainActor
@Test func aiSettingsDefaultsToProviderDefaultModel() throws {
    let settings = AISettings(provider: .anthropic)
    #expect(settings.model == AIProvider.anthropic.defaultModel)
}
