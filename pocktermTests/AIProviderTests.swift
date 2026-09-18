import Testing
import Foundation
@testable import pockterm

@Test @MainActor func everyProviderHasValidMetadata() {
    var keyIDs = Set<String>()
    for provider in AIProvider.allCases {
        #expect(!provider.defaultModel.isEmpty)
        #expect(!provider.displayName.isEmpty)
        #expect(provider.baseURL.scheme == "https")
        #expect(keyIDs.insert(provider.keychainKeyID).inserted)   // unique per provider
    }
}

@Test @MainActor func anthropicDefaultsToOpus() {
    #expect(AIProvider.anthropic.defaultModel == "claude-opus-4-8")
}
