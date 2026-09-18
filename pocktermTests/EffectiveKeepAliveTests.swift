import Testing
@testable import pockterm

@Test @MainActor func keepAliveHostValueWins() {
    #expect(EffectiveHostSettings.resolveKeepAlive(
        hostValue: 1800, chain: [900], globalDefault: 300) == 1800)
}

@Test @MainActor func keepAliveNearestGroupWhenHostInherits() {
    #expect(EffectiveHostSettings.resolveKeepAlive(
        hostValue: 0, chain: [nil, 900], globalDefault: 300) == 900)
}

@Test @MainActor func keepAliveGlobalWhenHostAndGroupsUnset() {
    #expect(EffectiveHostSettings.resolveKeepAlive(
        hostValue: 0, chain: [nil, nil], globalDefault: 1800) == 1800)
}

@Test @MainActor func keepAliveOffWhenNothingSet() {
    #expect(EffectiveHostSettings.resolveKeepAlive(
        hostValue: 0, chain: [], globalDefault: 0) == 0)
}
