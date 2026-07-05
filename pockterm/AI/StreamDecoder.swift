import Foundation

/// Decodes one Server-Sent-Events line into an assistant text delta (or nil for
/// non-text events). Pure so it can be unit-tested without networking.
struct StreamDecoder {
    let provider: AIProvider

    func text(from line: String) -> String? {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        switch provider {
        case .anthropic:
            guard json["type"] as? String == "content_block_delta",
                  let delta = json["delta"] as? [String: Any],
                  delta["type"] as? String == "text_delta"
            else { return nil }
            return delta["text"] as? String
        case .openai, .openRouter:
            guard let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any]
            else { return nil }
            return delta["content"] as? String
        }
    }
}
