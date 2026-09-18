import Testing
import SwiftData
@testable import pockterm

/// A manager with one session attached directly, bypassing `open` so no SSH
/// connection is attempted.
///
/// Holds the `ModelContainer`: a `ModelContext` does not retain its container,
/// and letting it deallocate resets the context and destroys every model
/// instance mid-test.
@MainActor
private struct Fixture {
    let container: ModelContainer
    let manager: SessionManager
    let session: TerminalSession
    let host: Host

    init() throws {
        container = try ModelContainer(
            for: Host.self, Identity.self, SSHKeyRecord.self, KnownHostRecord.self,
            HostGroup.self, Snippet.self, CommandHistory.self,
            configurations: .init(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        host = Host(label: "web", address: "10.0.0.1")
        ctx.insert(host)
        manager = SessionManager(secretStore: InMemorySecretStore(), modelContext: ctx)
        session = TerminalSession(host: host, secretStore: manager.secretStore, modelContext: ctx)
        manager.sessions = [session]
        manager.activeID = session.id
    }

    /// A second host registered in the same container.
    func insertHost(label: String, address: String) -> Host {
        let other = Host(label: label, address: address)
        container.mainContext.insert(other)
        return other
    }
}

@Test @MainActor func terminalPresentedWhenSessionOpen() throws {
    let f = try Fixture()
    #expect(f.manager.isTerminalPresented)
}

@Test @MainActor func minimizeHidesTerminalButKeepsSessionAlive() throws {
    let f = try Fixture()
    f.manager.minimize()
    #expect(!f.manager.isTerminalPresented)
    #expect(f.manager.sessions.count == 1)
    #expect(f.manager.activeID == f.session.id)
}

@Test @MainActor func revealRestoresMinimizedTerminal() throws {
    let f = try Fixture()
    f.manager.minimize()
    f.manager.reveal()
    #expect(f.manager.isTerminalPresented)
}

@Test @MainActor func minimizeWithNoSessionsIsNoOp() throws {
    let f = try Fixture()
    f.manager.sessions = []
    f.manager.activeID = nil
    f.manager.minimize()
    #expect(!f.manager.isMinimized)
    #expect(!f.manager.isTerminalPresented)
}

@Test @MainActor func closeAllClearsMinimizedState() throws {
    let f = try Fixture()
    f.manager.minimize()
    f.manager.closeAll()
    #expect(!f.manager.isMinimized)
    #expect(f.manager.sessions.isEmpty)
}

@Test @MainActor func sessionForHostFindsLiveSession() throws {
    let f = try Fixture()
    #expect(f.manager.session(for: f.host)?.id == f.session.id)

    let other = f.insertHost(label: "db", address: "10.0.0.2")
    #expect(f.manager.session(for: other) == nil)
}

@Test @MainActor func focusRevealsAndActivatesSession() throws {
    let f = try Fixture()
    let second = TerminalSession(host: f.insertHost(label: "db", address: "10.0.0.2"),
                                 secretStore: f.manager.secretStore,
                                 modelContext: f.container.mainContext)
    f.manager.sessions.append(second)
    f.manager.activeID = second.id
    f.manager.minimize()

    f.manager.focus(f.session)
    #expect(f.manager.activeID == f.session.id)
    #expect(f.manager.isTerminalPresented)
}
