import Foundation
import SwiftData
import SwiftTerm

/// One turn in the assistant transcript.
struct AssistantMessage: Identifiable {
    enum Role { case user, assistant, tool }
    let id = UUID()
    let role: Role
    var text: String
    /// For role .tool: which tool ran and how it ended.
    var toolName: String?
    var toolDetail: String?      // e.g. the command or path
    var toolResult: String?
    var denied = false

    /// Completed fenced code blocks in an assistant reply, offered to the user
    /// as commands to insert or run. A trailing unclosed fence (mid-stream) is
    /// ignored until its closing fence arrives.
    var commands: [String] {
        guard role == .assistant else { return [] }
        let parts = text.components(separatedBy: "```")
        var found: [String] = []
        for index in stride(from: 1, to: parts.count - 1, by: 2) {
            var block = parts[index]
            if let newline = block.firstIndex(of: "\n") {
                let tag = block[block.startIndex..<newline]
                    .trimmingCharacters(in: .whitespaces).lowercased()
                if ["", "bash", "sh", "zsh", "shell", "console", "terminal"].contains(tag) {
                    block = String(block[block.index(after: newline)...])
                }
            }
            let command = block
                .split(separator: "\n")
                .map { $0.hasPrefix("$ ") ? String($0.dropFirst(2)) : String($0) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !command.isEmpty { found.append(command) }
        }
        return found
    }
}

/// A tool call waiting for the user's Run/Deny, same continuation pattern as
/// PendingHostKey.
struct PendingToolApproval: Identifiable {
    let id = UUID()
    let call: ToolCall
    let resume: (Bool) -> Void
}

/// Drives the assistant chat for one terminal session: assembles context from
/// the live terminal buffer and attachments, runs the agent loop (streaming
/// replies, approving and executing tool calls), and can type a suggested
/// command back into the terminal.
@MainActor
@Observable
final class AssistantModel {
    /// The owning session (it holds this model strongly).
    private unowned let session: TerminalSession
    private let modelContext: ModelContext
    private let keyStore: AIKeyStore
    private let client = AIClient()
    private var streamTask: Task<Void, Never>?

    var messages: [AssistantMessage] = []
    var attachments: [ContextAttachment] = []
    var isStreaming = false
    var errorMessage: String?
    var pendingApproval: PendingToolApproval?

    /// Total budget for the system prompt (terminal tail + attachments).
    static let contextBudget = 24_000

    init(session: TerminalSession, secretStore: SecretStore, modelContext: ModelContext) {
        self.session = session
        self.modelContext = modelContext
        self.keyStore = AIKeyStore(secretStore: secretStore)
    }

    var settings: AISettings {
        AISettings.single(in: modelContext)
    }

    func send(_ prompt: String) {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }
        errorMessage = nil

        let provider = settings.activeProvider
        guard let apiKey = (try? keyStore.key(for: provider)) ?? nil, !apiKey.isEmpty else {
            errorMessage = "No API key for \(provider.displayName). Add one in Settings → AI Assistant."
            return
        }

        messages.append(AssistantMessage(role: .user, text: text))
        let system = ContextBuilder.systemPrompt(terminalText: terminalText(),
                                                 attachments: attachments,
                                                 maxChars: Self.contextBudget)
        // Merge consecutive same-role turns (e.g. after a failed reply was
        // discarded) — Anthropic requires user/assistant alternation.
        var turns: [ChatMessage] = []
        for message in messages where !message.text.isEmpty {
            let role: ChatMessage.Role = message.role == .user ? .user : .assistant
            if let last = turns.last, last.role == role {
                turns[turns.count - 1] = ChatMessage(role: role, text: last.text + "\n\n" + message.text)
            } else {
                turns.append(ChatMessage(role: role, text: message.text))
            }
        }
        var request = ChatRequest(model: settings.model, system: system, messages: turns)
        request.tools = AgentTools.specs

        messages.append(AssistantMessage(role: .assistant, text: ""))
        isStreaming = true
        let approvalMode = settings.agentApproval
        let loop = AgentLoop(client: client,
                             executor: SessionToolExecutor(session: session,
                                                           modelContext: modelContext))
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await loop.run(request: request, provider: provider, apiKey: apiKey,
                                   approve: { [weak self] call in
                                       await self?.approve(call, mode: approvalMode) ?? false
                                   },
                                   onEvent: { [weak self] event in self?.handle(event) })
            } catch is CancellationError {
                // User tapped stop; keep whatever streamed so far.
            } catch {
                errorMessage = error.localizedDescription
            }
            if messages.last?.role == .assistant, messages.last?.text.isEmpty == true {
                messages.removeLast()
            }
            isStreaming = false
        }
    }

    func stop() {
        if pendingApproval != nil { resolveApproval(false) }
        streamTask?.cancel()
    }

    private func approve(_ call: ToolCall, mode: AgentApproval) async -> Bool {
        switch mode {
        case .never: return true
        case .risky where !AgentTools.isMutating(call): return true
        default:
            return await withCheckedContinuation { continuation in
                pendingApproval = PendingToolApproval(call: call) { decision in
                    continuation.resume(returning: decision)
                }
            }
        }
    }

    func resolveApproval(_ approved: Bool) {
        pendingApproval?.resume(approved)
        pendingApproval = nil
    }

    private func handle(_ event: AgentLoop.Event) {
        switch event {
        case .assistantDelta(let delta):
            if messages.last?.role != .assistant {
                messages.append(AssistantMessage(role: .assistant, text: ""))
            }
            messages[messages.count - 1].text += delta
        case .assistantTurnEnded:
            if messages.last?.role == .assistant, messages.last?.text.isEmpty == true {
                messages.removeLast()
            }
        case .toolPending:
            break   // the approval card renders from pendingApproval
        case .toolStarted(let call):
            messages.append(AssistantMessage(role: .tool, text: "",
                                             toolName: call.name,
                                             toolDetail: Self.summary(of: call)))
        case .toolFinished(let call, let result):
            if let index = messages.lastIndex(where: {
                $0.role == .tool && $0.toolName == call.name && $0.toolResult == nil && !$0.denied
            }) {
                messages[index].toolResult = result
            }
        case .toolDenied(let call):
            var entry = AssistantMessage(role: .tool, text: "",
                                         toolName: call.name, toolDetail: Self.summary(of: call))
            entry.denied = true
            messages.append(entry)
        case .hitIterationCap:
            errorMessage = "Stopped after \(AgentLoop.maxIterations) agent steps."
        }
    }

    /// One-line human summary of a call for the transcript card.
    static func summary(of call: ToolCall) -> String {
        let args = call.arguments()
        return args["command"] as? String
            ?? args["path"] as? String
            ?? args["host"] as? String
            ?? args["label"] as? String
            ?? ""
    }

    /// Types the command into the terminal and presses Enter.
    func runCommand(_ command: String) {
        session.sendKeys(Array((command + "\n").utf8))
    }

    /// Types the command into the terminal without executing it.
    func insertCommand(_ command: String) {
        session.sendKeys(Array(command.utf8))
    }

    func addAttachment(name: String, data: Data) {
        let contents = String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
        attachments.append(ContextAttachment(name: name, contents: contents))
    }

    func removeAttachment(_ attachment: ContextAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    /// The session's full terminal buffer (scrollback included); ContextBuilder
    /// keeps only the tail that fits the budget.
    private func terminalText() -> String {
        let data = session.terminalView.getTerminal().getBufferAsData()
        return String(decoding: data, as: UTF8.self)
    }
}
