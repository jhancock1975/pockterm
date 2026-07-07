import Foundation

/// A tool the agent may call: name, human description, JSON-schema parameters.
struct ToolSpec {
    let name: String
    let description: String
    let parameters: [String: Any]
}

/// One tool invocation requested by the model.
struct ToolCall: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    /// Raw JSON arguments as streamed by the provider.
    let argumentsJSON: String

    func arguments() -> [String: Any] {
        guard let data = argumentsJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }
}
