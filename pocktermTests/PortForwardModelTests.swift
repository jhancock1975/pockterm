import Testing
import SwiftData
@testable import pockterm

@MainActor
@Test func portForwardPersistsWithHost() throws {
    let container = try ModelContainer(
        for: Host.self, Identity.self, SSHKeyRecord.self, KnownHostRecord.self,
        HostGroup.self, Snippet.self, PortForward.self,
        configurations: .init(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    let host = Host(label: "web", address: "1.1.1.1")
    let forward = PortForward(label: "db tunnel", type: .local, bindPort: 5432,
                              remoteHost: "10.0.0.9", remotePort: 5432, host: host)
    ctx.insert(forward)
    try ctx.save()

    let fetched = try ctx.fetch(FetchDescriptor<PortForward>())
    #expect(fetched.count == 1)
    #expect(fetched[0].type == .local)
    #expect(fetched[0].bindPort == 5432)
    #expect(fetched[0].remoteHost == "10.0.0.9")
    #expect(fetched[0].remotePort == 5432)
    #expect(fetched[0].host?.label == "web")
}
