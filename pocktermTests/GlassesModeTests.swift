import Testing
import Foundation
import SwiftData
@testable import pockterm

private let one = UUID(), two = UUID()

@Test @MainActor func noSessionsShowsTheIdleScreen() {
    #expect(GlassesContent.resolve(isPrimary: true, activeID: nil, sessionIDs: [],
                                   isMinimized: false) == .idle)
}

@Test @MainActor func anOpenSessionShowsItsTerminal() {
    #expect(GlassesContent.resolve(isPrimary: true, activeID: two, sessionIDs: [one, two],
                                   isMinimized: false) == .terminal(two))
}

@Test @MainActor func minimizingShowsTheIdleScreen() {
    #expect(GlassesContent.resolve(isPrimary: true, activeID: one, sessionIDs: [one],
                                   isMinimized: true) == .idle)
}

@Test @MainActor func anActiveIDWithNoSessionShowsTheIdleScreen() {
    // Mid-close: activeID can briefly name a session that is already gone.
    #expect(GlassesContent.resolve(isPrimary: true, activeID: two, sessionIDs: [one],
                                   isMinimized: false) == .idle)
}

@Test @MainActor func aSecondDisplayOnlyEverShowsTheIdleScreen() {
    #expect(GlassesContent.resolve(isPrimary: false, activeID: one, sessionIDs: [one],
                                   isMinimized: false) == .idle)
}

/// A private defaults domain per test, removed afterwards.
@MainActor
private func withDefaults(_ body: (UserDefaults) -> Void) {
    let name = "glasses-tests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    body(defaults)
    defaults.removePersistentDomain(forName: name)
}

@Test @MainActor func glassesTextStartsAt18() {
    withDefaults { #expect(GlassesTextSize.load(from: $0) == 18) }
}

@Test @MainActor func glassesTextSizeRoundTrips() {
    withDefaults { defaults in
        GlassesTextSize.save(22, to: defaults)
        #expect(GlassesTextSize.load(from: defaults) == 22)
    }
}

@Test @MainActor func glassesTextSizeIsClampedBothWays() {
    withDefaults { defaults in
        GlassesTextSize.save(4, to: defaults)
        #expect(GlassesTextSize.load(from: defaults) == TerminalZoom.minSize)
        defaults.set(99, forKey: GlassesTextSize.key)   // a value from outside the app
        #expect(GlassesTextSize.load(from: defaults) == TerminalZoom.maxSize)
    }
}

/// A manager with one session attached directly (no SSH), and its own
/// defaults domain so the glasses size never touches the real one.
@MainActor
private struct GlassesFixture {
    let container: ModelContainer   // a ModelContext doesn't retain its container
    let manager: SessionManager
    let session: TerminalSession
    let defaults: UserDefaults
    let suite = "glasses-fixture-\(UUID().uuidString)"

    init() throws {
        container = try ModelContainer(
            for: Host.self, Identity.self, SSHKeyRecord.self, KnownHostRecord.self,
            HostGroup.self, Snippet.self, CommandHistory.self,
            configurations: .init(isStoredInMemoryOnly: true))
        let ctx = container.mainContext
        let host = Host(label: "web", address: "10.0.0.1")
        ctx.insert(host)
        defaults = UserDefaults(suiteName: suite)!
        manager = SessionManager(secretStore: InMemorySecretStore(), modelContext: ctx,
                                 defaults: defaults)
        session = TerminalSession(host: host, secretStore: manager.secretStore, modelContext: ctx)
        manager.sessions = [session]
        manager.activeID = session.id
    }

    func tearDown() { defaults.removePersistentDomain(forName: suite) }
}

@Test @MainActor func glassesModeDrawsEverySessionAtTheGlassesSize() throws {
    let f = try GlassesFixture(); defer { f.tearDown() }
    f.manager.setGlassesMode(true)
    #expect(f.session.isGlassesMode)
    #expect(f.session.displayedFontSize == GlassesTextSize.defaultSize)
}

@Test @MainActor func leavingGlassesModeRestoresThePhoneZoom() throws {
    let f = try GlassesFixture(); defer { f.tearDown() }
    f.session.currentFontSize = 11
    f.manager.setGlassesMode(true)
    f.manager.setGlassesMode(false)
    #expect(!f.session.isGlassesMode)
    #expect(f.session.displayedFontSize == 11)
}

@Test @MainActor func glassesTextChangesApplyLiveAndAreRemembered() throws {
    let f = try GlassesFixture(); defer { f.tearDown() }
    f.manager.setGlassesMode(true)
    f.manager.setGlassesFontSize(24)
    #expect(f.session.displayedFontSize == 24)
    #expect(GlassesTextSize.load(from: f.defaults) == 24)
}

@Test @MainActor func glassesTextIsClampedAtTheManager() throws {
    let f = try GlassesFixture(); defer { f.tearDown() }
    f.manager.setGlassesFontSize(40)
    #expect(f.manager.glassesFontSize == TerminalZoom.maxSize)
}

@Test @MainActor func glassesTextChangesLeaveThePhoneAloneOutsideGlassesMode() throws {
    let f = try GlassesFixture(); defer { f.tearDown() }
    let phoneSize = f.session.displayedFontSize
    f.manager.setGlassesFontSize(26)
    #expect(f.session.displayedFontSize == phoneSize)
}

@Test @MainActor func aSessionKeepsOneFilesBrowser() throws {
    // The glasses-mode browser comes and goes with tab switches and
    // minimising. Its model, and any transfer in it, belongs to the session.
    let f = try GlassesFixture(); defer { f.tearDown() }
    #expect(f.session.files === f.session.files)
    #expect(f.session.files.host === f.session.host)
}

@Test @MainActor func glassesModeScrollsTheTerminalFromTheKeyBar() throws {
    let f = try GlassesFixture(); defer { f.tearDown() }
    let keyBar = try #require(f.session.terminalView.inputAccessoryView as? KeyBarView)
    #expect(!keyBar.scrollsLocally)
    f.manager.setGlassesMode(true)
    #expect(keyBar.scrollsLocally)
    f.manager.setGlassesMode(false)
    #expect(!keyBar.scrollsLocally)
}
