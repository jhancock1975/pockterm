import Foundation

/// One message in a chat exchange with the assistant.
struct ChatMessage: Equatable {
    enum Role: String { case system, user, assistant, tool }
    let role: Role
    let text: String
    /// Tool invocations attached to an assistant turn.
    var toolCalls: [ToolCall] = []
    /// For role .tool: which call this message answers.
    var toolCallID: String? = nil
}

/// A provider-agnostic chat request; `RequestEncoder` turns it into each
/// provider's wire format.
struct ChatRequest {
    let model: String
    /// System prompt (carries the terminal/file context). Kept separate so the
    /// Anthropic encoder can place it in the top-level `system` field.
    let system: String?
    /// User/assistant turns only — never the system prompt.
    var messages: [ChatMessage]
    var maxTokens: Int = 4096
    var tools: [ToolSpec] = []
}
