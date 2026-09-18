import Testing
@testable import pockterm

@Test @MainActor func parsesMultipleHostsAndSkipsWildcard() {
    let config = """
    # global
    Host *
        ForwardAgent yes

    Host web
        HostName 10.0.0.5
        User deploy
        Port 2222

    Host db
        hostname 10.0.0.6
        user postgres
    """
    let hosts = SSHConfigParser.parse(config)
    #expect(hosts.count == 2)

    let web = hosts.first { $0.alias == "web" }
    #expect(web?.hostName == "10.0.0.5")
    #expect(web?.user == "deploy")
    #expect(web?.port == 2222)

    let db = hosts.first { $0.alias == "db" }
    #expect(db?.hostName == "10.0.0.6")
    #expect(db?.user == "postgres")
    #expect(db?.port == nil)
}

@Test @MainActor func ignoresUnknownKeysAndComments() {
    let config = """
    Host only
        # a comment
        HostName example.com
        IdentityFile ~/.ssh/id_ed25519
    """
    let hosts = SSHConfigParser.parse(config)
    #expect(hosts.count == 1)
    #expect(hosts[0].alias == "only")
    #expect(hosts[0].hostName == "example.com")
    #expect(hosts[0].user == nil)
}
