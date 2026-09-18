import Testing
@testable import pockterm

@Test @MainActor func parsesGreeting() {
    #expect(SOCKS5.parseGreeting([5, 1, 0]) == true)
    #expect(SOCKS5.parseGreeting([5, 2, 0, 2]) == true)   // no-auth present
    #expect(SOCKS5.parseGreeting([5, 1, 2]) == false)     // only GSSAPI offered
    #expect(SOCKS5.parseGreeting([5]) == nil)             // incomplete
}

@Test @MainActor func parsesConnectIPv4() {
    let bytes: [UInt8] = [5, 1, 0, 1, 1, 2, 3, 4, 0, 80]
    let target = SOCKS5.parseConnect(bytes)
    #expect(target?.host == "1.2.3.4")
    #expect(target?.port == 80)
}

@Test @MainActor func parsesConnectDomain() {
    var bytes: [UInt8] = [5, 1, 0, 3, 11]
    bytes += Array("example.com".utf8)
    bytes += [0x01, 0xBB]   // 443
    let target = SOCKS5.parseConnect(bytes)
    #expect(target?.host == "example.com")
    #expect(target?.port == 443)
}

@Test @MainActor func incompleteConnectReturnsNil() {
    #expect(SOCKS5.parseConnect([5, 1, 0, 1, 1, 2]) == nil)
}
