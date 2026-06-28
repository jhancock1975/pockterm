import SwiftUI

/// Owns all open terminal sessions and which one is active. Sessions keep
/// running in the background until explicitly closed.
@MainActor
@Observable
final class SessionManager {
    var sessions: [TerminalSession] = []
    var activeID: TerminalSession.ID?
    let secretStore: SecretStore

    init(secretStore: SecretStore) {
        self.secretStore = secretStore
    }

    var active: TerminalSession? {
        sessions.first { $0.id == activeID }
    }

    func open(_ host: Host) {
        let session = TerminalSession(host: host, secretStore: secretStore)
        sessions.append(session)
        activeID = session.id
        Task { await session.start() }
    }

    func close(_ session: TerminalSession) {
        Task { await session.disconnect() }
        sessions.removeAll { $0.id == session.id }
        if activeID == session.id { activeID = sessions.last?.id }
    }

    func closeAll() {
        for session in sessions { Task { await session.disconnect() } }
        sessions.removeAll()
        activeID = nil
    }
}
