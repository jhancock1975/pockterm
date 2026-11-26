import Foundation

/// An AI provider the assistant can talk to using the user's own API key, or
/// the user's own server (`custom`), where a key is optional.
nonisolated enum AIProvider: String, CaseIterable, Codable, Identifiable {
    case anthropic
    case openai
    case openRouter
    case huggingFace
    case meta
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .openRouter: return "OpenRouter"
        case .huggingFace: return "Hugging Face"
        case .meta: return "Meta (Muse)"
        case .custom: return String(localized: "Self-Hosted")
        }
    }

    /// Sensible starting model; user-editable in settings.
    var defaultModel: String {
        switch self {
        case .anthropic: return "claude-opus-4-8"
        case .openai: return "gpt-4o"
        case .openRouter: return "openai/gpt-4o"
        case .huggingFace: return "openai/gpt-oss-120b"
        case .meta: return "muse-spark-1.3"
        // No sensible guess: the server's own list supplies it.
        case .custom: return ""
        }
    }

    /// Nil only for `custom` with no usable address saved.
    var baseURL: URL? {
        switch self {
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/messages")!
        case .openai: return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/chat/completions")!
        case .huggingFace: return URL(string: "https://router.huggingface.co/v1/chat/completions")!
        case .meta: return URL(string: "https://api.meta.ai/v1/chat/completions")!
        case .custom: return CustomServer.endpoints?.chat
        }
    }

    /// Endpoint listing the models this provider offers.
    var modelsURL: URL? {
        switch self {
        case .anthropic: return URL(string: "https://api.anthropic.com/v1/models")!
        case .openai: return URL(string: "https://api.openai.com/v1/models")!
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1/models")!
        case .huggingFace: return URL(string: "https://router.huggingface.co/v1/models")!
        case .meta: return URL(string: "https://api.meta.ai/v1/models")!
        case .custom: return CustomServer.endpoints?.models
        }
    }

    /// Where the user creates an API key for this provider. A self-hosted
    /// server has no such page.
    var apiKeyHelpURL: URL? {
        switch self {
        case .anthropic: return URL(string: "https://console.anthropic.com/settings/keys")!
        case .openai: return URL(string: "https://platform.openai.com/api-keys")!
        case .openRouter: return URL(string: "https://openrouter.ai/settings/keys")!
        case .huggingFace: return URL(string: "https://huggingface.co/settings/tokens")!
        case .meta: return URL(string: "https://dev.meta.ai")!
        case .custom: return nil
        }
    }

    /// Ollama and llama-server take no key unless they were set up to.
    var requiresAPIKey: Bool { self != .custom }

    /// Stable identifier used as the SecretStore key for this provider's API key.
    var keychainKeyID: String { "ai.key.\(rawValue)" }
}
