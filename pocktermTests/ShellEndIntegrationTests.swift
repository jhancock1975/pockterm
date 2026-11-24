import Testing
import Foundation
@testable import pockterm

/// Records what an interactive shell's end looked like.
actor ShellEndBox {
    var end: ShellEnd?
    var output = ""
    func set(_ e: ShellEnd) { end = e }
    func append(_ bytes: [UInt8]) { output += String(decoding: bytes, as: UTF8.self) }
}

/// Integration against a throwaway sshd on 127.0.0.1:2223 (start it with
/// `scripts/reconnect-test-sshd`). Skips when nothing is listening. Tells
/// apart the two ways a shell ends, which is what auto-reconnect keys off:
/// the user typing `exit`, and the server side of the connection dying.
private func testCredentials() -> SSHCredentials? {
    let path = ProcessInfo.processInfo.environment["POCKTERM_RECONNECT_KEY"]
        ?? "/tmp/pockterm-reconnect-sshd/client_ed25519"
    guard let pem = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
    return SSHCredentials(host: "127.0.0.1", port: 2223, username: ProcessInfo.processInfo.environment["POCKTERM_RECONNECT_USER"] ?? "john",
                          auth: .openSSHKey(pem: pem, passphrase: nil))
}

private func runShell(sending command: String) async throws -> (ShellEnd?, String) {
    let creds = try #require(testCredentials())
    let engine = SSHEngine()
    let box = ShellEndBox()
    try await engine.connect(creds) { _ in true }
    try await engine.openShell(cols: 80, rows: 24,
                               onOutput: { bytes in Task { await box.append(bytes) } },
                               onClose: { end in Task { await box.set(end) } })
    try await Task.sleep(for: .milliseconds(800))
    await engine.send(Array(command.utf8))
    for _ in 0..<50 where await box.end == nil {
        try await Task.sleep(for: .milliseconds(100))
    }
    let end = await box.end
    let output = await box.output
    await engine.disconnect()
    return (end, output)
}

@Test func typingExitEndsTheShellWithTheConnectionUp() async throws {
    guard sshReachable(host: "127.0.0.1", port: 2223), testCredentials() != nil else { return }
    let (end, output) = try await runShell(sending: "exit\n")
    #expect(end == .exited, "output: \(output.suffix(80).debugDescription)")
}

@Test func killingTheServerSideDropsTheConnection() async throws {
    guard sshReachable(host: "127.0.0.1", port: 2223), testCredentials() != nil else { return }
    // The shell's parent is this connection's sshd process: killing it is a
    // server-side drop, the same as the server going away.
    let (end, output) = try await runShell(sending: "kill -9 $PPID\n")
    #expect(end == .connectionLost, "output: \(output.suffix(80).debugDescription)")
}
