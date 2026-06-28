import Testing
@testable import pockterm

@MainActor
@Test func hostValueOverridesGroup() {
    let g = HostGroup(name: "g", defaultPort: 2222)
    let h = Host(label: "h", address: "a", port: 22, group: g)
    let eff = EffectiveHostSettings.resolve(host: h)
    #expect(eff.port == 22)
}

@MainActor
@Test func groupDefaultUsedWhenHostUnset() {
    let id = Identity(label: "i", username: "u", authMethod: .password)
    let g = HostGroup(name: "g", defaultIdentity: id, defaultPort: 2222)
    // Host with no explicit identity and sentinel port 0 means "inherit".
    let h = Host(label: "h", address: "a", port: 0, identity: nil, group: g)
    let eff = EffectiveHostSettings.resolve(host: h)
    #expect(eff.port == 2222)
    #expect(eff.identity?.username == "u")
}

@MainActor
@Test func nestedParentGroupDefaultUsed() {
    let parent = HostGroup(name: "parent", defaultPort: 8022)
    let child = HostGroup(name: "child", parent: parent) // child defines nothing
    let h = Host(label: "h", address: "a", port: 0, group: child)
    let eff = EffectiveHostSettings.resolve(host: h)
    #expect(eff.port == 8022)
}

@MainActor
@Test func defaultPort22WhenNothingSet() {
    let h = Host(label: "h", address: "a", port: 0)
    let eff = EffectiveHostSettings.resolve(host: h)
    #expect(eff.port == 22)
    #expect(eff.identity == nil)
}
