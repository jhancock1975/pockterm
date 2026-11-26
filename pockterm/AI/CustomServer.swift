import Foundation

/// The address of a self-hosted model server (Ollama, llama.cpp's
/// llama-server, LM Studio, vLLM, …). All of them serve the OpenAI chat
/// completions API under `/v1`, so one address is enough to reach both the
/// chat and the model-list endpoints.
///
/// Kept in UserDefaults rather than SwiftData: it is not a secret, and the
/// provider enum has to read it from anywhere, off the main actor included.
nonisolated enum CustomServer {
    static let addressKey = "ai.custom.address"

    static var address: String {
        get { UserDefaults.standard.string(forKey: addressKey) ?? "" }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines),
                                        forKey: addressKey) }
    }

    /// The chat and model-list URLs for whatever the user typed. Accepts a
    /// bare `192.168.1.20:11434`, a full `http://pc.local:8080/v1`, or the
    /// chat URL itself copied from a server's docs. Nil when it isn't an
    /// address at all.
    static func endpoints(from raw: String) -> (chat: URL, models: URL)? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "http://" + text }
        guard var parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = parts.host, !host.isEmpty
        else { return nil }
        parts.query = nil
        parts.fragment = nil

        var path = parts.path
        while path.hasSuffix("/") { path.removeLast() }
        for suffix in ["/chat/completions", "/models"] where path.hasSuffix(suffix) {
            path.removeLast(suffix.count)
        }
        if !path.hasSuffix("/v1") { path += "/v1" }

        parts.path = path + "/chat/completions"
        guard let chat = parts.url else { return nil }
        parts.path = path + "/models"
        guard let models = parts.url else { return nil }
        return (chat, models)
    }

    /// The endpoints for the saved address.
    static var endpoints: (chat: URL, models: URL)? { endpoints(from: address) }
}

/// The assistant was pointed at a self-hosted server without saying where.
struct MissingServerAddressError: LocalizedError {
    var errorDescription: String? {
        String(localized: "Enter your server's address in Settings → AI Assistant.")
    }
}
