import Testing
import SwiftData
@testable import pockterm

// These tests insert every model into an in-memory container before touching
// relationships: reading relationships on unmanaged @Model instances (no
// container anywhere) has hung the test host for the full 600 s watchdog
// window on the iOS 26.5 simulator, killing every queued @MainActor test.
//
// Each test must hold the ModelContainer itself for its whole body — a
// ModelContext does NOT keep its container alive, and using a context whose
// container was deallocated traps inside SwiftData.
@MainActor
private func makeContainer() throws -> ModelContainer {
    try ModelContainer(
        for: Host.self, Identity.self, SSHKeyRecord.self, KnownHostRecord.self,
        HostGroup.self, Snippet.self,
        configurations: .init(isStoredInMemoryOnly: true))
}

@MainActor
@Test func hostValueOverridesGroup() throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    let g = HostGroup(name: "g", defaultPort: 2222)
    ctx.insert(g)
    let h = Host(label: "h", address: "a", port: 22)
    ctx.insert(h)
    h.group = g
    let eff = EffectiveHostSettings.resolve(host: h)
    #expect(eff.port == 22)
}

@MainActor
@Test func groupDefaultUsedWhenHostUnset() throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    let id = Identity(label: "i", username: "u", authMethod: .password)
    ctx.insert(id)
    let g = HostGroup(name: "g", defaultPort: 2222)
    ctx.insert(g)
    g.defaultIdentity = id
    // Host with no explicit identity and sentinel port 0 means "inherit".
    let h = Host(label: "h", address: "a", port: 0, identity: nil)
    ctx.insert(h)
    h.group = g
    let eff = EffectiveHostSettings.resolve(host: h)
    #expect(eff.port == 2222)
    #expect(eff.identity?.username == "u")
}

@MainActor
@Test func nestedParentGroupDefaultUsed() throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    let parent = HostGroup(name: "parent", defaultPort: 8022)
    ctx.insert(parent)
    let child = HostGroup(name: "child") // child defines nothing
    ctx.insert(child)
    child.parent = parent
    let h = Host(label: "h", address: "a", port: 0)
    ctx.insert(h)
    h.group = child
    let eff = EffectiveHostSettings.resolve(host: h)
    #expect(eff.port == 8022)
}

@MainActor
@Test func defaultPort22WhenNothingSet() throws {
    let container = try makeContainer()
    let ctx = container.mainContext
    let h = Host(label: "h", address: "a", port: 0)
    ctx.insert(h)
    let eff = EffectiveHostSettings.resolve(host: h)
    #expect(eff.port == 22)
    #expect(eff.identity == nil)
}
