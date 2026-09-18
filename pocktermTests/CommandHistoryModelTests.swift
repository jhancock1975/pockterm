import Testing
import Foundation
import SwiftData
@testable import pockterm

@Test @MainActor func commandHistoryPersists() throws {
    let container = try ModelContainer(
        for: Host.self, Identity.self, SSHKeyRecord.self, KnownHostRecord.self,
        HostGroup.self, Snippet.self, PortForward.self, CommandHistory.self,
        configurations: .init(isStoredInMemoryOnly: true))
    let ctx = container.mainContext
    let entry = CommandHistory(hostID: UUID(), command: "git status")
    entry.count = 3
    ctx.insert(entry)
    try ctx.save()

    let fetched = try ctx.fetch(FetchDescriptor<CommandHistory>())
    #expect(fetched.count == 1)
    #expect(fetched[0].command == "git status")
    #expect(fetched[0].count == 3)
}
