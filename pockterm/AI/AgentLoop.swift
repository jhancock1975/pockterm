import Foundation

/// Abstraction over AIClient's streaming call so the agent loop can be tested
/// against a scripted fake.
protocol ChatStreaming: Sendable {
    func stream(_ request: ChatRequest, provider: AIProvider,
                apiKey: String) async -> AsyncThrowingStream<AIStreamEvent, Error>
}

extension AIClient: ChatStreaming {}

/// The agent: streams a reply, and while the model keeps requesting tools,
/// gets each call approved, executes it, appends the result, and goes again.
/// Ends on a plain reply, a thrown stream error, or the iteration cap.
@MainActor
final class AgentLoop {
    enum Event {
        case assistantDelta(String)
        case assistantTurnEnded
        case toolPending(ToolCall)
        case toolStarted(ToolCall)
        case toolFinished(ToolCall, result: String)
        case toolDenied(ToolCall)
        case hitIterationCap
    }

    static let maxIterations = 20

    private let client: ChatStreaming
    private let executor: AgentToolExecuting

    init(client: ChatStreaming, executor: AgentToolExecuting) {
        self.client = client
        self.executor = executor
    }

    func run(request: ChatRequest, provider: AIProvider, apiKey: String,
             approve: @escaping (ToolCall) async -> Bool,
             onEvent: @escaping (Event) -> Void) async throws {
        var messages = request.messages

        for _ in 0..<Self.maxIterations {
            var current = request
            current.messages = messages

            var streamedText = ""
            var toolCalls: [ToolCall] = []
            for try await event in await client.stream(current, provider: provider, apiKey: apiKey) {
                switch event {
                case .text(let delta):
                    streamedText += delta
                    onEvent(.assistantDelta(delta))
                case .toolCall(let call):
                    toolCalls.append(call)
                }
            }
            onEvent(.assistantTurnEnded)
            messages.append(ChatMessage(role: .assistant, text: streamedText,
                                        toolCalls: toolCalls))
            guard !toolCalls.isEmpty else { return }

            for call in toolCalls {
                onEvent(.toolPending(call))
                if await approve(call) {
                    onEvent(.toolStarted(call))
                    let result = await executor.execute(call)
                    onEvent(.toolFinished(call, result: result))
                    messages.append(ChatMessage(role: .tool, text: result, toolCallID: call.id))
                } else {
                    onEvent(.toolDenied(call))
                    messages.append(ChatMessage(role: .tool,
                                                text: "The user declined this tool call.",
                                                toolCallID: call.id))
                }
                try Task.checkCancellation()
            }
        }
        onEvent(.hitIterationCap)
    }
}
