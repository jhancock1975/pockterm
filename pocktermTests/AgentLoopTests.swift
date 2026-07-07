import Testing
@testable import pockterm

/// Yields a scripted list of event-lists, one per stream() call, and records
/// each request it was asked to send.
final class FakeChat: ChatStreaming, @unchecked Sendable {
    var turns: [[AIStreamEvent]]
    var requests: [ChatRequest] = []
    init(turns: [[AIStreamEvent]]) { self.turns = turns }

    func stream(_ request: ChatRequest, provider: AIProvider,
                apiKey: String) async -> AsyncThrowingStream<AIStreamEvent, Error> {
        requests.append(request)
        let turn = turns.isEmpty ? [] : turns.removeFirst()
        return AsyncThrowingStream { continuation in
            for event in turn { continuation.yield(event) }
            continuation.finish()
        }
    }
}

final class FakeExecutor: AgentToolExecuting, @unchecked Sendable {
    var executed: [ToolCall] = []
    func execute(_ call: ToolCall) async -> String {
        executed.append(call)
        return "ok:\(call.name)"
    }
}

private func makeRequest() -> ChatRequest {
    ChatRequest(model: "m", system: nil,
                messages: [ChatMessage(role: .user, text: "do it")])
}

@Test @MainActor func runsToolThenContinuesUntilPlainReply() async throws {
    let call = ToolCall(id: "c1", name: "run_command", argumentsJSON: #"{"command":"ls"}"#)
    let chat = FakeChat(turns: [[.toolCall(call)], [.text("done")]])
    let executor = FakeExecutor()
    let loop = AgentLoop(client: chat, executor: executor)
    var events: [AgentLoop.Event] = []
    try await loop.run(request: makeRequest(), provider: .openai, apiKey: "k",
                       approve: { _ in true }, onEvent: { events.append($0) })
    #expect(executor.executed == [call])
    #expect(chat.requests.count == 2)
    // Second request carries the assistant tool turn + the tool result.
    let followUp = chat.requests[1].messages
    #expect(followUp.contains { $0.role == .assistant && $0.toolCalls == [call] })
    #expect(followUp.contains { $0.role == .tool && $0.toolCallID == "c1" && $0.text == "ok:run_command" })
    #expect(events.contains { if case .assistantDelta("done") = $0 { return true }; return false })
}

@Test @MainActor func denialSendsDeclinedResultAndContinues() async throws {
    let call = ToolCall(id: "c1", name: "write_file", argumentsJSON: "{}")
    let chat = FakeChat(turns: [[.toolCall(call)], [.text("understood")]])
    let executor = FakeExecutor()
    let loop = AgentLoop(client: chat, executor: executor)
    try await loop.run(request: makeRequest(), provider: .openai, apiKey: "k",
                       approve: { _ in false }, onEvent: { _ in })
    #expect(executor.executed.isEmpty)
    #expect(chat.requests[1].messages.contains {
        $0.role == .tool && $0.text.contains("declined")
    })
}

@Test @MainActor func iterationCapStopsRunawayLoop() async throws {
    let call = ToolCall(id: "c", name: "run_command", argumentsJSON: #"{"command":"ls"}"#)
    let chat = FakeChat(turns: Array(repeating: [.toolCall(call)], count: 30))
    let loop = AgentLoop(client: chat, executor: FakeExecutor())
    var capped = false
    try await loop.run(request: makeRequest(), provider: .openai, apiKey: "k",
                       approve: { _ in true },
                       onEvent: { if case .hitIterationCap = $0 { capped = true } })
    #expect(capped)
    #expect(chat.requests.count == AgentLoop.maxIterations)
}
