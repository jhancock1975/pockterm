import Foundation

/// A tool the agent may call: name, human description, JSON-schema parameters.
/// `@unchecked Sendable` because `parameters` is a JSON-schema
/// `[String: Any]`, which the compiler can never prove Sendable. Every stored
/// property is a `let` and nothing mutates one after construction, so the
/// value is immutable in practice — but the guarantee is by inspection here,
/// not by the type system. Changing `parameters` to a typed JSON enum would
/// remove the need for this.
nonisolated struct ToolSpec: @unchecked Sendable {
    let name: String
    let description: String
    let parameters: [String: Any]
}

/// One tool invocation requested by the model.
nonisolated struct ToolCall: Equatable, Sendable, Identifiable {
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
