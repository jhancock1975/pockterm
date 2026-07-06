import Foundation

/// Error from the AI HTTP layer, mapped to a user-readable message.
struct AIClientError: LocalizedError {
    let status: Int
    let detail: String

    var errorDescription: String? {
        switch status {
        case 401, 403: return "The API key was rejected. Check it in AI Settings."
        case 404: return "Unknown model. Check the model name in AI Settings."
        case 429: return "Rate limited by the provider. Try again shortly."
        case 529: return "The provider is overloaded. Try again shortly."
        default:
            let trimmed = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Request failed (HTTP \(status))."
                                   : "Request failed (HTTP \(status)): \(trimmed.prefix(200))"
        }
    }
}

/// Streams a chat completion over URLSession, yielding assistant text deltas
/// as they arrive.
actor AIClient {
    func stream(_ request: ChatRequest, provider: AIProvider,
                apiKey: String) -> AsyncThrowingStream<String, Error> {
        var urlRequest = URLRequest(url: provider.baseURL)
        urlRequest.httpMethod = "POST"
        for (field, value) in RequestEncoder.headers(for: provider, apiKey: apiKey) {
            urlRequest.setValue(value, forHTTPHeaderField: field)
        }
        urlRequest.httpBody = try? JSONSerialization.data(
            withJSONObject: RequestEncoder.body(for: request, provider: provider))

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: urlRequest)
                    if let http = response as? HTTPURLResponse,
                       !(200..<300).contains(http.statusCode) {
                        var detail = ""
                        for try await line in bytes.lines {
                            detail += line
                            if detail.count > 2_000 { break }
                        }
                        throw AIClientError(status: http.statusCode, detail: detail)
                    }
                    let decoder = StreamDecoder(provider: provider)
                    for try await line in bytes.lines {
                        if let delta = decoder.text(from: line) {
                            continuation.yield(delta)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// One-token round trip used by the settings screen's "Test" button.
    func validate(provider: AIProvider, model: String, apiKey: String) async throws {
        let probe = ChatRequest(model: model, system: nil,
                                messages: [ChatMessage(role: .user, text: "hi")],
                                maxTokens: 1)
        for try await _ in stream(probe, provider: provider, apiKey: apiKey) { break }
    }
}
