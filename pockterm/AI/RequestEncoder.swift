import Foundation

/// Turns a provider-agnostic `ChatRequest` into each provider's HTTP body and
/// headers. Pure so it can be unit-tested without networking.
enum RequestEncoder {
    static func body(for request: ChatRequest, provider: AIProvider) -> [String: Any] {
        let turns = request.messages.map { ["role": $0.role.rawValue, "content": $0.text] }
        switch provider {
        case .anthropic:
            // Anthropic /v1/messages takes the system prompt as a top-level field.
            var body: [String: Any] = [
                "model": request.model,
                "max_tokens": request.maxTokens,
                "stream": true,
                "messages": turns,
            ]
            if let system = request.system { body["system"] = system }
            return body
        case .openai, .openRouter:
            // Chat Completions carries the system prompt as a leading message.
            var messages: [[String: String]] = []
            if let system = request.system {
                messages.append(["role": "system", "content": system])
            }
            messages += turns
            return [
                "model": request.model,
                "max_tokens": request.maxTokens,
                "stream": true,
                "messages": messages,
            ]
        }
    }

    static func headers(for provider: AIProvider, apiKey: String) -> [String: String] {
        var headers = ["content-type": "application/json"]
        switch provider {
        case .anthropic:
            headers["x-api-key"] = apiKey
            headers["anthropic-version"] = "2023-06-01"
        case .openai:
            headers["Authorization"] = "Bearer \(apiKey)"
        case .openRouter:
            headers["Authorization"] = "Bearer \(apiKey)"
            headers["HTTP-Referer"] = "https://github.com/jhancock1975/pockterm"
            headers["X-Title"] = "Pockterm"
        }
        return headers
    }
}
