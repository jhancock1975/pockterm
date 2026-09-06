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
@Test func presentsRealHostKeyFingerprintFromLocalhost() async throws {
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
@Test func presentsRSAHostKeyFingerprintFromLegacyServer() async throws {
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
