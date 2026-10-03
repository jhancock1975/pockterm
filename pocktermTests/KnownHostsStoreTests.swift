import Testing
import Foundation
import SwiftData
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

// MARK: - Asking about a host key with nothing open

/// A connection owner with its own in-memory trust store. `answer` is what the
/// user taps; `openWhenAsked` records how many attempts were mid-handshake at
/// the moment the prompt appeared.
@MainActor
private final class Owner: HostKeyDeciding {
    let container: ModelContainer   // a ModelContext doesn't retain its container
    let modelContext: ModelContext
    var answer = true
    var openAttempts = 0
    var openWhenAsked: [Int] = []
    var pendingHostKey: PendingHostKey? {
        didSet {
            guard let pending = pendingHostKey else { return }
            openWhenAsked.append(openAttempts)
            let answer = answer
            Task { @MainActor in self.pendingHostKey = nil; pending.resume(answer) }
        }
    }
    init() throws {
        container = try ModelContainer(for: KnownHostRecord.self,
                                       configurations: .init(isStoredInMemoryOnly: true))
        modelContext = container.mainContext
    }
    var fingerprints: [String] {
        ((try? modelContext.fetch(FetchDescriptor<KnownHostRecord>())) ?? []).map(\.fingerprintSHA256)
    }
}

@MainActor private final class Attempts { var count = 0 }
private struct Refused: Error {}
private let webKey = PresentedHostKey(address: "web", port: 22, keyType: "ssh-ed25519",
                                      fingerprint: "SHA256:AAA")

/// One simulated SSH attempt: the handshake shows the key and goes on to log in
/// only if it's accepted.
@MainActor
private func attempt(_ owner: Owner, _ attempts: Attempts,
                     _ validate: @escaping @Sendable (PresentedHostKey) async -> Bool) async throws -> String {
    attempts.count += 1
    owner.openAttempts += 1
    defer { owner.openAttempts -= 1 }
    guard await validate(webKey) else { throw Refused() }
    return "logged in"
}

@Test @MainActor func aNewHostKeyIsAskedAboutWithNoConnectionOpen() async throws {
    // Citadel gives a login ten seconds, prompt included. Asked mid-handshake,
    // anyone who read the fingerprint first got "Connection Failed".
    let owner = try Owner(), attempts = Attempts()
    let result = try await owner.connectCheckingHostKey { try await attempt(owner, attempts, $0) }
    #expect(result == "logged in")
    #expect(owner.openWhenAsked == [0])
    #expect(attempts.count == 2)
    #expect(owner.fingerprints == ["SHA256:AAA"])
}

@Test @MainActor func aChangedHostKeyIsAskedAboutWithNoConnectionOpen() async throws {
    let owner = try Owner(), attempts = Attempts()
    owner.modelContext.insert(KnownHostRecord(hostAddress: "web", port: 22, keyType: "ssh-ed25519",
                                              fingerprintSHA256: "SHA256:OLD"))
    _ = try await owner.connectCheckingHostKey { try await attempt(owner, attempts, $0) }
    #expect(owner.openWhenAsked == [0])
    #expect(owner.fingerprints == ["SHA256:AAA"])
}

@Test @MainActor func rejectingAHostKeyStopsThere() async throws {
    let owner = try Owner(), attempts = Attempts()
    owner.answer = false
    await #expect(throws: HostKeyError.self) {
        _ = try await owner.connectCheckingHostKey { try await attempt(owner, attempts, $0) }
    }
    #expect(attempts.count == 1)
    #expect(owner.fingerprints.isEmpty)
}

@Test @MainActor func aTrustedHostKeyConnectsFirstTime() async throws {
    let owner = try Owner(), attempts = Attempts()
    owner.modelContext.insert(KnownHostRecord(hostAddress: "web", port: 22, keyType: "ssh-ed25519",
                                              fingerprintSHA256: "SHA256:AAA"))
    let result = try await owner.connectCheckingHostKey { try await attempt(owner, attempts, $0) }
    #expect(result == "logged in")
    #expect(attempts.count == 1)
    #expect(owner.openWhenAsked.isEmpty)
}

@Test @MainActor func aFailureBeforeTheHostKeyIsNotRetried() async throws {
    let owner = try Owner(), attempts = Attempts()
    await #expect(throws: Refused.self) {
        _ = try await owner.connectCheckingHostKey { _ -> String in
            attempts.count += 1
            throw Refused()   // connection refused, DNS failure, and the like
        }
    }
    #expect(attempts.count == 1)
    #expect(owner.openWhenAsked.isEmpty)
}

@Test @MainActor func aRejectedHostKeySaysSo() {
    #expect(HostKeyError.rejected.localizedDescription == "Host key rejected.")
}
