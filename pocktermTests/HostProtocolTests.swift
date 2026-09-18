import Testing
import SwiftData
@testable import pockterm

@Test @MainActor func hostProtocolDefaultsToSSH() {
    let host = Host(label: "web", address: "10.0.0.1")
    #expect(host.hostProtocol == .ssh)
    #expect(host.protocolRaw == "ssh")
}

@Test @MainActor func hostProtocolRoundTrips() {
    let host = Host(label: "files", address: "10.0.0.2", hostProtocol: .sftp)
    #expect(host.hostProtocol == .sftp)
    #expect(host.protocolRaw == "sftp")

    host.hostProtocol = .ssh
    #expect(host.protocolRaw == "ssh")
}

/// A store written by a newer build could carry a protocol this build has never
/// heard of. Degrading to SSH keeps the host usable instead of losing it.
@Test @MainActor func unknownStoredProtocolFallsBackToSSH() {
    let host = Host(label: "web", address: "10.0.0.1")
    host.protocolRaw = "quic-someday"
    #expect(host.hostProtocol == .ssh)
}

@Test @MainActor func hostProtocolPersists() throws {
    let container = try ModelContainer(
        for: Host.self, Identity.self, SSHKeyRecord.self, KnownHostRecord.self,
        HostGroup.self, Snippet.self,
        configurations: .init(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    ctx.insert(Host(label: "files", address: "10.0.0.2", hostProtocol: .sftp))
    try ctx.save()

    let fetched = try ctx.fetch(FetchDescriptor<Host>())
    #expect(fetched.count == 1)
    #expect(fetched[0].hostProtocol == .sftp)
}
