import Testing
import Foundation
@testable import pockterm

@Test @MainActor func everyProviderHasValidMetadata() {
    var keyIDs = Set<String>()
    for provider in AIProvider.allCases {
        #expect(!provider.displayName.isEmpty)
        #expect(keyIDs.insert(provider.keychainKeyID).inserted)   // unique per provider
        // A self-hosted server's address, model and key are the user's own.
        guard provider.requiresAPIKey else { continue }
        #expect(!provider.defaultModel.isEmpty)
        #expect(provider.baseURL?.scheme == "https")
        #expect(provider.apiKeyHelpURL?.scheme == "https")
    }
}

@Test @MainActor func anthropicDefaultsToOpus() {
    #expect(AIProvider.anthropic.defaultModel == "claude-opus-4-8")
}

@Test @MainActor func metaDefaultsToMuseSpark() {
    #expect(AIProvider.meta.defaultModel == "muse-spark-1.3")
    #expect(AIProvider.meta.displayName == "Meta (Muse)")
}
