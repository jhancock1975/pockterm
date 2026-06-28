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
