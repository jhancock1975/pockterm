import SwiftUI
import SwiftData

/// Owns all open terminal sessions and which one is active. Sessions keep
/// running in the background until explicitly closed.
@MainActor
@Observable
final class SessionManager {
    var sessions: [TerminalSession] = []
    var activeID: TerminalSession.ID?
    /// Terminal hidden while its sessions stay connected. Distinct from having
    /// no sessions, so dismissing the terminal never disconnects anything.
    private(set) var isMinimized = false
    let secretStore: SecretStore
    let modelContext: ModelContext

    init(secretStore: SecretStore, modelContext: ModelContext) {
        self.secretStore = secretStore
        self.modelContext = modelContext
    }

    var active: TerminalSession? {
        sessions.first { $0.id == activeID }
    }

    /// Drives the terminal's full-screen cover.
    var isTerminalPresented: Bool {
        !sessions.isEmpty && !isMinimized
    }

    /// The live session for a host, if one is already open.
    func session(for host: Host) -> TerminalSession? {
        let hostID = host.id
        return sessions.first { $0.host.id == hostID }
    }

    func open(_ host: Host) {
        let session = TerminalSession(host: host, secretStore: secretStore, modelContext: modelContext)
        session.sessionManager = self
        sessions.append(session)
        activeID = session.id
        isMinimized = false
        Task { await session.start() }
    }

    /// Brings an already-open session back on screen.
    func focus(_ session: TerminalSession) {
        activeID = session.id
        reveal()
    }

    func minimize() {
        guard !sessions.isEmpty else { return }
        isMinimized = true
    }

    func reveal() {
        isMinimized = false
    }

    func close(_ session: TerminalSession) {
        Task { await session.disconnect() }
        sessions.removeAll { $0.id == session.id }
        if activeID == session.id { activeID = sessions.last?.id }
        if sessions.isEmpty { isMinimized = false }
    }

    func closeAll() {
        for session in sessions { Task { await session.disconnect() } }
        sessions.removeAll()
        activeID = nil
        isMinimized = false
    }
}
