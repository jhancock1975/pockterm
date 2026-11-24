import Testing
import Foundation
import CryptoKit
@testable import pockterm

/// The parts of Secure Enclave keys that don't need an enclave. The simulator
/// has none, so signing with a real enclave key and logging in with it is
/// checked on the Mac instead (see `scripts/enclave-key-check`).

private func fields(of openSSH: String) -> (type: String, blob: [Data], comment: String) {
    let parts = openSSH.split(separator: " ").map(String.init)
    var data = Data(base64Encoded: parts[1])!
    var out: [Data] = []
    while data.count >= 4 {
        let len = Int(data.prefix(4).reduce(0) { $0 << 8 | UInt32($1) })
        data = data.dropFirst(4)
        out.append(Data(data.prefix(len)))
        data = data.dropFirst(len)
    }
    return (parts[0], out, parts[2])
}

@Test func enclavePublicKeyIsAnOpenSSHNistP256Line() {
    let key = P256.Signing.PrivateKey().publicKey
    let line = EnclaveKey.openSSHPublicKey(key, comment: "phone@pockterm")
    let f = fields(of: line)
    #expect(f.type == "ecdsa-sha2-nistp256")
    #expect(f.comment == "phone@pockterm")
    #expect(f.blob.count == 3)
    #expect(String(data: f.blob[0], encoding: .utf8) == "ecdsa-sha2-nistp256")
    #expect(String(data: f.blob[1], encoding: .utf8) == "nistp256")
    #expect(f.blob[2] == key.x963Representation)
    #expect(f.blob[2].count == 65 && f.blob[2].first == 0x04)
}

@Test func enclaveBlobSurvivesItsWrapper() {
    let blob = Data((0..<284).map { UInt8($0 % 251) })
    let pem = EnclaveKey.pem(fromBlob: blob)
    #expect(EnclaveKey.blob(fromPEM: pem) == blob)
}

@Test func enclaveAndEd25519WrappersDoNotReadEachOther() {
    let ed = KeyManager.generateEd25519(comment: "x").privateKeyPEM
    #expect(EnclaveKey.blob(fromPEM: ed) == nil)
    let enclave = EnclaveKey.pem(fromBlob: Data(repeating: 7, count: 32))
    // Same length as an Ed25519 seed on purpose: only the markers may decide.
    #expect(EnclaveKey.blob(fromPEM: enclave) != nil)
}
