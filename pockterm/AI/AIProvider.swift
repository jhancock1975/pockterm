import Foundation

/// An AI provider the assistant can talk to using the user's own API key.
enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case anthropic
    case openai
    case openRouter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .openRouter: return "OpenRouter"
        }
    }

    /// Sensible starting model; user-editable in settings.
    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-opus-4-8"
        case .openai: return "gpt-4o"
        case .openRouter: return "openai/gpt-4o"
        }
    }

    var baseURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")!
        case .openai: return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        }
    }

    /// Endpoint listing the models this provider offers.
    var modelsURL: URL {
        switch self {
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/models")!
        case .openai: return URL(string: "https://api.openai.com/v1/models")!
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/models")!
        }
    }

    /// Stable identifier used as the SecretStore key for this provider's API key.
    var keychainKeyID: String { "ai.key.\(rawValue)" }
}
