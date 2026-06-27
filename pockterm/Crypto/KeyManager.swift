import Foundation
import CryptoKit

struct GeneratedKey {
    let privateKeyPEM: String
    let publicKeyOpenSSH: String
    let keyType: String
}

/// Generates Ed25519 key pairs and encodes the public half in OpenSSH
/// `authorized_keys` format. The private half is stored as the raw 32-byte
/// seed, base64'd inside a Pockterm-specific PEM wrapper; `SSHEngine` and the
/// terminal session reconstruct the `Curve25519` key from that seed.
enum KeyManager {
    static let beginMarker = "-----BEGIN POCKTERM ED25519 PRIVATE KEY-----"
    static let endMarker = "-----END POCKTERM ED25519 PRIVATE KEY-----"

    static func generateEd25519(comment: String) -> GeneratedKey {
        let priv = Curve25519.Signing.PrivateKey()
        let pub = priv.publicKey.rawRepresentation
        let openssh = openSSHPublicKey(fromEd25519: pub, comment: comment)
        let seed = priv.rawRepresentation.base64EncodedString()
        let pem = "\(beginMarker)\n\(seed)\n\(endMarker)\n"
        return GeneratedKey(privateKeyPEM: pem, publicKeyOpenSSH: openssh, keyType: "ssh-ed25519")
    }

    /// Reconstructs the 32-byte Ed25519 seed from a Pockterm private-key PEM.
    static func seed(fromPEM pem: String) -> Data? {
        let body = pem
            .split(separator: "\n")
            .filter { !$0.hasPrefix("-----") }
            .joined()
        guard let data = Data(base64Encoded: body), data.count == 32 else { return nil }
        return data
    }

    static func openSSHPublicKey(fromEd25519 raw: Data, comment: String) -> String {
        func lengthPrefixed(_ d: Data) -> Data {
            var out = Data()
            var len = UInt32(d.count).bigEndian
            withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
            out.append(d)
            return out
        }
        var blob = Data()
        blob.append(lengthPrefixed(Data("ssh-ed25519".utf8)))
        blob.append(lengthPrefixed(raw))
        return "ssh-ed25519 \(blob.base64EncodedString()) \(comment)"
    }
}
