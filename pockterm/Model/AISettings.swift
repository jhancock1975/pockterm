import Foundation
import SwiftData

/// The assistant's configuration: which provider to talk to and with which
/// model. A single row; API keys live in the Keychain, never here.
@Model final class AISettings {
    var activeProviderRaw: String
    var model: String

    init(provider: AIProvider = .anthropic, model: String? = nil) {
        self.activeProviderRaw = provider.rawValue
        self.model = model ?? provider.defaultModel
    }

    var activeProvider: AIProvider {
        get { AIProvider(rawValue: activeProviderRaw) ?? .anthropic }
        set { activeProviderRaw = newValue.rawValue }
    }
}
