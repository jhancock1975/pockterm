import Foundation
import SwiftData
import SwiftTerm

/// One turn in the assistant transcript.
struct AssistantMessage: Identifiable {
    enum Role { case user, assistant }
    let id = UUID()
    let role: Role
    var text: String

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

/// Drives the assistant chat for one terminal session: assembles context from
/// the live terminal buffer and attachments, streams the reply, and can type
/// a suggested command back into the terminal.
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
        let request = ChatRequest(model: settings.model, system: system, messages: turns)

        messages.append(AssistantMessage(role: .assistant, text: ""))
        isStreaming = true
        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in await client.stream(request, provider: provider, apiKey: apiKey) {
                    if case .text(let delta) = event {
                        messages[messages.count - 1].text += delta
                    }
                }
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
        streamTask?.cancel()
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
