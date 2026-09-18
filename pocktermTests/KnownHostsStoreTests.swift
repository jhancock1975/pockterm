import Testing
import Foundation
@testable import pockterm

@Test @MainActor func tofuThenMatchThenMismatch() {
    let store = KnownHostsStore()
    let none: [KnownHostRecord] = []
    #expect(store.evaluate(address: "h", port: 22, keyType: "ssh-ed25519",
        presentedFingerprint: "SHA256:AAA", against: none) == .trustedNew(fingerprint: "SHA256:AAA"))

    let known = [KnownHostRecord(hostAddress: "h", port: 22, keyType: "ssh-ed25519", fingerprintSHA256: "SHA256:AAA")]
    #expect(store.evaluate(address: "h", port: 22, keyType: "ssh-ed25519",
        presentedFingerprint: "SHA256:AAA", against: known) == .matches)
    #expect(store.evaluate(address: "h", port: 22, keyType: "ssh-ed25519",
        presentedFingerprint: "SHA256:BBB", against: known) == .mismatch(stored: "SHA256:AAA", presented: "SHA256:BBB"))
}

@Test @MainActor func fingerprintFormat() {
    let fp = KnownHostsStore.fingerprintSHA256(ofHostKey: Data([1, 2, 3]))
    #expect(fp.hasPrefix("SHA256:"))
    #expect(!fp.contains("="))
}
