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
protocol HostKeyDeciding: AnyObject {
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
