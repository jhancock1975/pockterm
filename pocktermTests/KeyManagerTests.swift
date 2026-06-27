import Testing
import Foundation
@testable import pockterm

@Test func generatesEd25519OpenSSHPublicKey() {
    let key = KeyManager.generateEd25519(comment: "john@pockterm")
    #expect(key.keyType == "ssh-ed25519")
    #expect(key.publicKeyOpenSSH.hasPrefix("ssh-ed25519 "))
    #expect(key.publicKeyOpenSSH.hasSuffix(" john@pockterm"))

    // The base64 blob decodes and its first length-prefixed string is the algorithm name.
    let blob = key.publicKeyOpenSSH.split(separator: " ")[1]
    let data = Data(base64Encoded: String(blob))!
    let len = data.prefix(4).reduce(0) { ($0 << 8) | Int($1) }
    let algo = String(data: data[4..<(4 + len)], encoding: .utf8)
    #expect(algo == "ssh-ed25519")
}

@Test func privateKeyPEMRoundTripsToSeed() {
    let key = KeyManager.generateEd25519(comment: "c")
    let body = key.privateKeyPEM
        .split(separator: "\n")
        .filter { !$0.hasPrefix("-----") }
        .joined()
    let seed = Data(base64Encoded: body)
    #expect(seed?.count == 32)
}
