import Testing
import Foundation
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
