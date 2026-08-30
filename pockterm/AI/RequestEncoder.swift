import Foundation

/// Turns a provider-agnostic `ChatRequest` into each provider's HTTP body and
/// headers. Pure so it can be unit-tested without networking.
enum RequestEncoder {
    static func body(for request: ChatRequest, provider: AIProvider) -> [String: Any] {
        switch provider {
        case .anthropic:
            // Anthropic /v1/messages takes the system prompt as a top-level field.
            var body: [String: Any] = [
                "model": request.model,
                "max_tokens": request.maxTokens,
                "stream": true,
                "messages": anthropicMessages(request.messages),
            ]
            if let system = request.system { body["system"] = system }
            if !request.tools.isEmpty {
                body["tools"] = request.tools.map {
                    ["name": $0.name, "description": $0.description, "input_schema": $0.parameters]
                }
            }
            return body
        case .openai, .openRouter, .huggingFace:
            // Chat Completions carries the system prompt as a leading message.
            var messages: [[String: Any]] = []
            if let system = request.system {
                messages.append(["role": "system", "content": system])
            }
            messages += openAIMessages(request.messages)
            // OpenAI deprecated max_tokens; gpt-5/o-series reject it with a 400.
            // OpenRouter's normalized schema still expects max_tokens.
            let tokenField = provider == .openai ? "max_completion_tokens" : "max_tokens"
            var body: [String: Any] = [
                "model": request.model,
                tokenField: request.maxTokens,
                "stream": true,
                "messages": messages,
            ]
            if !request.tools.isEmpty {
                body["tools"] = request.tools.map {
                    ["type": "function",
                     "function": ["name": $0.name, "description": $0.description,
                                  "parameters": $0.parameters]]
                }
            }
            return body
        }
    }

    /// OpenAI Chat Completions turns: assistant tool calls ride a `tool_calls`
    /// array; results are role-"tool" messages keyed by `tool_call_id`.
    private static func openAIMessages(_ messages: [ChatMessage]) -> [[String: Any]] {
        messages.map { message in
            switch message.role {
            case .tool:
                return ["role": "tool", "tool_call_id": message.toolCallID ?? "",
                        "content": message.text]
            case .assistant where !message.toolCalls.isEmpty:
                var entry: [String: Any] = ["role": "assistant"]
                if !message.text.isEmpty { entry["content"] = message.text }
                entry["tool_calls"] = message.toolCalls.map {
                    ["id": $0.id, "type": "function",
                     "function": ["name": $0.name, "arguments": $0.argumentsJSON]]
                }
                return entry
            default:
                return ["role": message.role.rawValue, "content": message.text]
            }
        }
    }

    /// Anthropic Messages turns: assistant tool calls are `tool_use` content
    /// blocks; results are `tool_result` blocks inside a user turn.
    private static func anthropicMessages(_ messages: [ChatMessage]) -> [[String: Any]] {
        messages.map { message in
            switch message.role {
            case .tool:
                return ["role": "user",
                        "content": [["type": "tool_result",
                                     "tool_use_id": message.toolCallID ?? "",
                                     "content": message.text]]]
            case .assistant where !message.toolCalls.isEmpty:
                var blocks: [[String: Any]] = []
                if !message.text.isEmpty { blocks.append(["type": "text", "text": message.text]) }
                blocks += message.toolCalls.map {
                    ["type": "tool_use", "id": $0.id, "name": $0.name, "input": $0.arguments()]
                }
                return ["role": "assistant", "content": blocks]
            default:
                return ["role": message.role.rawValue, "content": message.text]
            }
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
            // OpenRouter uses this for attribution. It pointed at the repo,
            // which is private and 404s; nothing public may link to GitHub.
            headers["HTTP-Referer"] = "https://pockterm.com"
            headers["X-Title"] = "Pockterm"
        case .huggingFace:
            headers["Authorization"] = "Bearer \(apiKey)"
        }
        return headers
    }
}
