import Testing
import SwiftData
@testable import pockterm

@MainActor
@Test func hostPersistsWithIdentity() throws {
    let container = try ModelContainer(
        for: Host.self, Identity.self, SSHKeyRecord.self, KnownHostRecord.self,
        HostGroup.self, Snippet.self,
        configurations: .init(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    let id = Identity(label: "prod", username: "root", authMethod: .password)
    let host = Host(label: "web", address: "10.0.0.1", port: 22, identity: id)
    ctx.insert(host)
    try ctx.save()
    let fetched = try ctx.fetch(FetchDescriptor<Host>())
    #expect(fetched.count == 1)
    #expect(fetched[0].identity?.username == "root")
    #expect(fetched[0].port == 22)
}
