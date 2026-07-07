import Foundation

/// What a streaming chat response yields: text deltas as they arrive, and
/// complete tool calls once all their argument fragments have streamed in.
enum AIStreamEvent: Equatable, Sendable {
    case text(String)
    case toolCall(ToolCall)
}

/// Decodes Server-Sent-Events lines into `AIStreamEvent`s, accumulating
/// streamed tool-call fragments (both providers deliver arguments in chunks).
/// Pure state machine over strings so it unit-tests without networking.
final class StreamDecoder {
    let provider: AIProvider
    private struct Partial { var id = ""; var name = ""; var args = "" }
    private var partials: [Int: Partial] = [:]
    private var flushed = false

    init(provider: AIProvider) { self.provider = provider }

    func events(from line: String) -> [AIStreamEvent] {
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        switch provider {
        case .anthropic: return anthropicEvents(json)
        case .openai, .openRouter, .huggingFace: return openAIEvents(json)
        }
    }

    /// Flush any tool calls still pending at stream end (OpenAI signals
    /// completion via finish_reason on the last delta, which may race [DONE]).
    func finish() -> [AIStreamEvent] {
        guard !flushed else { return [] }
        flushed = true
        let events = partials.sorted { $0.key < $1.key }.map {
            AIStreamEvent.toolCall(ToolCall(id: $0.value.id, name: $0.value.name,
                                            argumentsJSON: $0.value.args))
        }
        partials.removeAll()
        return events
    }

    private func anthropicEvents(_ json: [String: Any]) -> [AIStreamEvent] {
        let index = json["index"] as? Int ?? 0
        switch json["type"] as? String {
        case "content_block_start":
            if let block = json["content_block"] as? [String: Any],
               block["type"] as? String == "tool_use" {
                partials[index] = Partial(id: block["id"] as? String ?? "",
                                          name: block["name"] as? String ?? "")
            }
            return []
        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any] else { return [] }
            if delta["type"] as? String == "text_delta", let text = delta["text"] as? String {
                return [.text(text)]
            }
            if delta["type"] as? String == "input_json_delta",
               let chunk = delta["partial_json"] as? String {
                partials[index]?.args += chunk
            }
            return []
        case "content_block_stop":
            guard let partial = partials.removeValue(forKey: index) else { return [] }
            return [.toolCall(ToolCall(id: partial.id, name: partial.name,
                                       argumentsJSON: partial.args))]
        default:
            return []
        }
    }

    private func openAIEvents(_ json: [String: Any]) -> [AIStreamEvent] {
        guard let choice = (json["choices"] as? [[String: Any]])?.first else { return [] }
        if let delta = choice["delta"] as? [String: Any] {
            if let calls = delta["tool_calls"] as? [[String: Any]] {
                for call in calls {
                    let index = call["index"] as? Int ?? 0
                    var partial = partials[index] ?? Partial()
                    if let id = call["id"] as? String { partial.id = id }
                    if let function = call["function"] as? [String: Any] {
                        if let name = function["name"] as? String { partial.name = name }
                        if let chunk = function["arguments"] as? String { partial.args += chunk }
                    }
                    partials[index] = partial
                }
            }
            if let text = delta["content"] as? String { return [.text(text)] }
        }
        if choice["finish_reason"] as? String == "tool_calls" { return finish() }
        return []
    }
}
