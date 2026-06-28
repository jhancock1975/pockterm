import Testing
import SwiftData
@testable import pockterm

@MainActor
@Test func hostBelongsToGroupAndFavorite() throws {
    let c = try ModelContainer(for: Host.self, Identity.self, SSHKeyRecord.self,
                               KnownHostRecord.self, HostGroup.self, Snippet.self,
                               configurations: .init(isStoredInMemoryOnly: true))
    let ctx = c.mainContext
    let g = HostGroup(name: "prod")
    let h = Host(label: "web", address: "1.1.1.1")
    h.group = g
    h.isFavorite = true
    ctx.insert(h)
    try ctx.save()
    let fetched = try ctx.fetch(FetchDescriptor<Host>())
    #expect(fetched.first?.group?.name == "prod")
    #expect(fetched.first?.isFavorite == true)
}

@MainActor
@Test func snippetPersists() throws {
    let c = try ModelContainer(for: Host.self, Identity.self, SSHKeyRecord.self,
                               KnownHostRecord.self, HostGroup.self, Snippet.self,
                               configurations: .init(isStoredInMemoryOnly: true))
    let ctx = c.mainContext
    ctx.insert(Snippet(label: "ll", command: "ls -la"))
    try ctx.save()
    #expect(try ctx.fetch(FetchDescriptor<Snippet>()).first?.command == "ls -la")
}
