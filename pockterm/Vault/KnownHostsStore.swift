import Foundation
import CryptoKit

enum HostTrustDecision: Equatable {
    case trustedNew(fingerprint: String)
    case matches
    case mismatch(stored: String, presented: String)
}

/// Trust-on-first-use evaluation for SSH host keys. Pure logic over the set of
/// stored `KnownHostRecord`s so it can be unit-tested without a live server.
nonisolated struct KnownHostsStore {
    func evaluate(address: String, port: Int, keyType: String,
                  presentedFingerprint: String, against records: [KnownHostRecord]) -> HostTrustDecision {
        if let existing = records.first(where: {
            $0.hostAddress == address && $0.port == port && $0.keyType == keyType
        }) {
            return existing.fingerprintSHA256 == presentedFingerprint
                ? .matches
                : .mismatch(stored: existing.fingerprintSHA256, presented: presentedFingerprint)
        }
        return .trustedNew(fingerprint: presentedFingerprint)
    }

    /// OpenSSH-style SHA256 fingerprint of a raw host-key blob.
    static func fingerprintSHA256(ofHostKey blob: Data) -> String {
        let digest = SHA256.hash(data: blob)
        let b64 = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")
        return "SHA256:\(b64)"
    }
}
