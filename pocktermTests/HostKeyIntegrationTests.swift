import Testing
import Foundation
@testable import pockterm

/// Captures the fingerprint presented during a real connection.
actor FingerprintBox {
    var fingerprint: String?
    var keyType = ""
    func set(_ fp: String?, _ type: String) { fingerprint = fp; keyType = type }
}

/// Integration test against a live SSH server on localhost (the Mac's sshd,
/// reachable from the simulator). Skips cleanly when no server is listening so
/// it doesn't fail on machines/CI without one. Auth is intentionally wrong —
/// host-key validation happens first, which is what we're verifying.
@Test @MainActor func presentsRealHostKeyFingerprintFromLocalhost() async throws {
    guard sshReachable(host: "127.0.0.1", port: 22) else { return }

    let engine = SSHEngine()
    let box = FingerprintBox()
    let creds = SSHCredentials(host: "127.0.0.1", port: 22,
                               username: "pockterm-test", auth: .password("definitely-wrong"))
    _ = try? await engine.connect(creds) { presented in
        await box.set(presented.fingerprint, presented.keyType)
        return false  // reject so the connection stops at host-key validation
    }
    await engine.disconnect()

    let fingerprint = await box.fingerprint
    let keyType = await box.keyType
    print("CAPTURED_HOSTKEY fp=\(fingerprint ?? "nil") type=\(keyType)")

    #expect(fingerprint != nil)
    #expect(fingerprint?.hasPrefix("SHA256:") == true)
    // SHA256 digest is 32 bytes -> 43 unpadded base64 chars.
    #expect(fingerprint?.count == "SHA256:".count + 43)
}

/// The same thing against a server of the older shape: an RSA host key, group
/// 14 key exchange, AES-CTR. Before `SSHAlgorithms.pockterm` registered those,
/// pockterm could not negotiate with such a server at all — it never got as far
/// as presenting a host key, so there was nothing for the user to trust or
/// refuse. Skips cleanly when nothing is listening on 2222.
///
/// To run it, put an sshd on 2222 that will offer nothing else:
///
///     ssh-keygen -t rsa -b 2048 -f /tmp/legacy/host_rsa -N ""
///     /usr/sbin/sshd -f /tmp/legacy/sshd_config -e -D &
///
/// with `HostKey /tmp/legacy/host_rsa`, `HostKeyAlgorithms ssh-rsa`,
/// `KexAlgorithms diffie-hellman-group14-sha256`, `Ciphers aes128-ctr`,
/// `MACs hmac-sha2-256`, `Port 2222`, `ListenAddress 127.0.0.1`. It does not
/// need to run as root: authentication is deliberately wrong here, because
/// host-key validation happens first and is the whole point.
@Test @MainActor func presentsRSAHostKeyFingerprintFromLegacyServer() async throws {
    guard sshReachable(host: "127.0.0.1", port: 2222) else { return }

    let engine = SSHEngine()
    let box = FingerprintBox()
    let creds = SSHCredentials(host: "127.0.0.1", port: 2222,
                               username: "pockterm-test", auth: .password("definitely-wrong"))
    _ = try? await engine.connect(creds) { presented in
        await box.set(presented.fingerprint, presented.keyType)
        return false
    }
    await engine.disconnect()

    let fingerprint = await box.fingerprint
    let keyType = await box.keyType
    print("CAPTURED_RSA_HOSTKEY fp=\(fingerprint ?? "nil") type=\(keyType)")

    // "unknown" with a nil fingerprint is what this used to produce, and it is
    // the failure that matters: an unidentifiable key at the trust prompt.
    #expect(keyType == "ssh-rsa")
    #expect(fingerprint?.hasPrefix("SHA256:") == true)
    #expect(fingerprint?.count == "SHA256:".count + 43)
}

/// End to end, the thing the whole RSA change is for: a key the user already
/// had, imported, authenticating against a server that speaks only the older
/// algorithms. Skips unless all three pieces are present — the fixture (see
/// `KeyManagerTests` for how to make it), its public half in the Mac's
/// `~/.ssh/authorized_keys`, and the sshd on 2222.
///
/// That sshd needs `PubkeyAcceptedAlgorithms +ssh-rsa`, which is itself the
/// point worth remembering: Citadel signs with `ssh-rsa`, i.e. SHA-1, and
/// current OpenSSH refuses SHA-1 RSA client signatures by default.
@Test @MainActor func authenticatesWithAnImportedRSAKey() async throws {
    guard sshReachable(host: "127.0.0.1", port: 2222),
          let pem = keyFixture("rsa_plain"),
          let username = keyFixture("username")?.trimmingCharacters(in: .whitespacesAndNewlines),
          !username.isEmpty
    else { return }

    let engine = SSHEngine()
    let creds = SSHCredentials(host: "127.0.0.1", port: 2222, username: username,
                               auth: .openSSHKey(pem: pem, passphrase: nil))
    // Throwing fails the test: reaching this point means the key parsed, the
    // signature verified server-side, and the session came up.
    try await engine.connect(creds) { _ in true }
    await engine.disconnect()
    print("IMPORTED_RSA_AUTH ok as \(username)")
}

private func keyFixture(_ name: String) -> String? {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    return try? String(contentsOf: documents.appending(path: "testkeys/\(name)"), encoding: .utf8)
}

private func sshReachable(host: String, port: UInt16) -> Bool {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    guard fd >= 0 else { return false }
    defer { close(fd) }
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = port.bigEndian
    _ = inet_pton(AF_INET, host, &addr.sin_addr)
    let result = withUnsafePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    return result == 0
}
