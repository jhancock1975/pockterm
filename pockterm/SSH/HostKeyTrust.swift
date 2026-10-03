import Foundation
import SwiftData

/// A host key awaiting the user's accept/reject decision.
struct PendingHostKey: Identifiable {
    let id = UUID()
    let info: PresentedHostKey
    /// Non-nil means the presented key differs from a previously trusted one.
    let storedFingerprint: String?
    let resume: (Bool) -> Void
}

/// The trust-on-first-use flow shared by every connection owner (terminal,
/// files browser, port forwards). Conformers supply their SwiftData context and
/// the slot their UI watches for a pending prompt; the decision itself lives
/// here so the call sites cannot drift apart — a divergence between them would
/// mean one connection path silently pinning host keys differently from
/// another.
@MainActor
protocol HostKeyDeciding: AnyObject, Sendable {
    var modelContext: ModelContext { get }
    var pendingHostKey: PendingHostKey? { get set }
}

extension HostKeyDeciding {
    /// Matches a presented host key against the stored `KnownHostRecord`s. New
    /// or changed keys prompt the user, and an accepted key is persisted.
    func decideHostKey(_ info: PresentedHostKey) async -> Bool {
        let records = (try? modelContext.fetch(FetchDescriptor<KnownHostRecord>())) ?? []

        guard let fingerprint = info.fingerprint else {
            // Couldn't derive a fingerprint; ask the user without persisting.
            return await promptForHostKey(info: info, storedFingerprint: nil)
        }

        switch KnownHostsStore().evaluate(address: info.address, port: info.port,
                                          keyType: info.keyType,
                                          presentedFingerprint: fingerprint,
                                          against: records) {
        case .matches:
            return true
        case .trustedNew:
            let accepted = await promptForHostKey(info: info, storedFingerprint: nil)
            if accepted {
                modelContext.insert(KnownHostRecord(hostAddress: info.address, port: info.port,
                                                    keyType: info.keyType,
                                                    fingerprintSHA256: fingerprint))
                try? modelContext.save()
            }
            return accepted
        case .mismatch(let stored, let presented):
            let accepted = await promptForHostKey(info: info, storedFingerprint: stored)
            if accepted, let record = records.first(where: {
                $0.hostAddress == info.address && $0.port == info.port && $0.keyType == info.keyType
            }) {
                record.fingerprintSHA256 = presented
                try? modelContext.save()
            }
            return accepted
        }
    }

    func promptForHostKey(info: PresentedHostKey, storedFingerprint: String?) async -> Bool {
        await withCheckedContinuation { continuation in
            pendingHostKey = PendingHostKey(info: info, storedFingerprint: storedFingerprint) { decision in
                continuation.resume(returning: decision)
            }
        }
    }
}

extension HostKeyDeciding {
    /// Whether a presented key is already trusted for its host, without asking.
    func hostKeyIsTrusted(_ info: PresentedHostKey) -> Bool {
        guard let fingerprint = info.fingerprint else { return false }
        let records = (try? modelContext.fetch(FetchDescriptor<KnownHostRecord>())) ?? []
        return KnownHostsStore().evaluate(address: info.address, port: info.port,
                                          keyType: info.keyType,
                                          presentedFingerprint: fingerprint,
                                          against: records) == .matches
    }

    /// Makes one SSH connection with host-key checking, and asks the user about
    /// a new or changed key while no connection is open.
    ///
    /// Citadel gives a login ten seconds from TCP connect to authenticated, and
    /// a prompt answered inside the handshake counts against them, so anyone who
    /// stopped to read the fingerprint got "Connection Failed" as they tapped
    /// Accept. Instead the attempt that meets an untrusted key refuses it at
    /// once, the user is asked with nothing open, and if they accept, the key is
    /// stored and a fresh attempt finds it trusted. `attempt` makes one
    /// connection, handing `validate` to the SSH layer.
    func connectCheckingHostKey<T>(
        _ attempt: (_ validate: @escaping @Sendable (PresentedHostKey) async -> Bool) async throws -> T
    ) async throws -> T {
        let untrusted = UntrustedKey()
        do {
            return try await attempt { [weak self] presented in
                guard let self else { return false }
                if await self.hostKeyIsTrusted(presented) { return true }
                await untrusted.set(presented)
                return false
            }
        } catch {
            guard let presented = await untrusted.key else { throw error }
            guard await decideHostKey(presented) else { throw HostKeyError.rejected }
            return try await attempt { [weak self] presented in
                await self?.decideHostKey(presented) ?? false
            }
        }
    }
}

/// The key a refused attempt met, carried out of the SSH layer's callback.
private actor UntrustedKey {
    private(set) var key: PresentedHostKey?
    func set(_ key: PresentedHostKey) { self.key = key }
}
