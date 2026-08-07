import Foundation
import SwiftData

/// Live tool executor for one terminal session: commands run on an exec
/// channel of the session's SSH connection; file tools use a lazily opened
/// SFTP connection to the same host (host-key prompts reuse the session's
/// TOFU flow). Every branch returns text for the model — errors included, so
/// the agent can react instead of dying.
@MainActor
final class SessionToolExecutor: AgentToolExecuting {
    private unowned let session: TerminalSession
    private let modelContext: ModelContext
    private var sftp: SFTPService?

    /// Byte budget for text returned to the model from any one tool call.
    static let outputBudget = 16_000

    init(session: TerminalSession, modelContext: ModelContext) {
        self.session = session
        self.modelContext = modelContext
    }

    func execute(_ call: ToolCall) async -> String {
        let args = call.arguments()
        do {
            switch call.name {
            case "run_command":
                guard let command = args["command"] as? String else { return "error: missing 'command'" }
                let output = try await session.engine.exec(command)
                return Self.truncate(output.isEmpty ? "(no output)" : output)
            case "read_file":
                guard let path = args["path"] as? String else { return "error: missing 'path'" }
                let data = try await sftpService().downloadData(path)
                return Self.truncate(String(decoding: data, as: UTF8.self))
            case "write_file":
                guard let path = args["path"] as? String,
                      let content = args["content"] as? String else {
                    return "error: missing 'path' or 'content'"
                }
                try await sftpService().upload(Data(content.utf8), to: path)
                return "wrote \(content.utf8.count) bytes to \(path)"
            case "list_files":
                let path = args["path"] as? String ?? "."
                let files = try await sftpService().list(path)
                return Self.truncate(files.map {
                    "\($0.kind == .directory ? "d" : "-") \($0.size)\t\($0.name)"
                }.joined(separator: "\n"))
            case "open_session":
                guard let label = args["host"] as? String else { return "error: missing 'host'" }
                let hosts = (try? modelContext.fetch(FetchDescriptor<Host>())) ?? []
                guard let host = hosts.first(where: { $0.label == label }) else {
                    return "error: no saved host labeled '\(label)'. Saved hosts: \(hosts.map(\.label).joined(separator: ", "))"
                }
                session.sessionManager?.open(host)
                return "opened a session to \(label)"
            case "save_snippet":
                guard let label = args["label"] as? String,
                      let command = args["command"] as? String else {
                    return "error: missing 'label' or 'command'"
                }
                modelContext.insert(Snippet(label: label, command: command))
                try? modelContext.save()
                return "saved snippet '\(label)'"
            default:
                return "error: unknown tool '\(call.name)'"
            }
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    private func sftpService() async throws -> SFTPService {
        if let sftp { return sftp }
        guard case .success(let creds) = HostConnection.credentials(for: session.host,
                                                                    secretStore: session.secretStore)
        else { throw SSHEngineError.notConnected }
        let service = SFTPService()
        try await service.connect(creds) { [weak session] presented in
            await session?.decideHostKey(presented) ?? false
        }
        sftp = service
        return service
    }

    static func truncate(_ text: String, budget: Int = outputBudget) -> String {
        guard text.utf8.count > budget else { return text }
        return String(text.prefix(budget)) + "\n…[truncated]"
    }
}
