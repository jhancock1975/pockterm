import Testing
@testable import pockterm

// Inheritance is tested through the pure resolver with plain String
// identities — deliberately no SwiftData. Walking @Model relationships here
// hung the test host on the iOS 26.5 simulator (600 s watchdog kill on
// 2026-07-06/07; later profiled as a 60 s+ main-thread stall in SwiftData's
// AnyKeyPath hashing), which poisoned every queued @MainActor test. The thin
// SwiftData walk in resolve(host:) is exercised by the simulator smoke run.

@Test @MainActor func hostValueOverridesGroup() {
    let r = EffectiveHostSettings.resolve(hostPort: 22, hostIdentity: String?.none,
                                          chain: [(port: 2222, identity: nil)])
    #expect(r.port == 22)
}

@Test @MainActor func groupDefaultUsedWhenHostUnset() {
    // Host port 0 is the "inherit" sentinel; no host identity.
    let r = EffectiveHostSettings.resolve(hostPort: 0, hostIdentity: String?.none,
                                          chain: [(port: 2222, identity: "group-id")])
    #expect(r.port == 2222)
    #expect(r.identity == "group-id")
}

@Test @MainActor func nestedParentGroupDefaultUsed() {
    // Child group defines nothing; the parent's default applies.
    let r = EffectiveHostSettings.resolve(
        hostPort: 0, hostIdentity: String?.none,
        chain: [(port: nil, identity: nil), (port: 8022, identity: nil)])
    #expect(r.port == 8022)
}

@Test @MainActor func nearestAncestorWinsOverFarther() {
    let r = EffectiveHostSettings.resolve(
        hostPort: 0, hostIdentity: String?.none,
        chain: [(port: 2022, identity: "near"), (port: 8022, identity: "far")])
    #expect(r.port == 2022)
    #expect(r.identity == "near")
}

@Test @MainActor func hostIdentityWinsOverChain() {
    let r = EffectiveHostSettings.resolve(hostPort: 0, hostIdentity: "mine",
                                          chain: [(port: nil, identity: "group-id")])
    #expect(r.identity == "mine")
}

@Test @MainActor func defaultPort22WhenNothingSet() {
    let r = EffectiveHostSettings.resolve(hostPort: 0, hostIdentity: String?.none, chain: [])
    #expect(r.port == 22)
    #expect(r.identity == nil)
}
