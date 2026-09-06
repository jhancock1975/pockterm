import Foundation
import Crypto
import NIOCore
import NIOSSH

/// A host key presented by a server during connection, reduced to the bits the
/// UI needs to make a trust decision.
struct PresentedHostKey: Sendable {
    let address: String
    let port: Int
    let keyType: String
    /// OpenSSH-style `SHA256:…` fingerprint, or nil if it couldn't be derived.
    let fingerprint: String?
}

enum HostKeyError: Error { case rejected }

/// Bridges Citadel/NIOSSH host-key validation to an async accept/reject
/// decision supplied by the app.
final class CallbackHostKeyValidator: NIOSSHClientServerAuthenticationDelegate {
    private let address: String
    private let port: Int
    private let decide: @Sendable (PresentedHostKey) async -> Bool

    init(address: String, port: Int, decide: @escaping @Sendable (PresentedHostKey) async -> Bool) {
        self.address = address
        self.port = port
        self.decide = decide
    }

    func validateHostKey(hostKey: NIOSSHPublicKey, validationCompletePromise: EventLoopPromise<Void>) {
        let inspected = HostKeyInspector.inspect(hostKey)
        let presented = PresentedHostKey(address: address, port: port,
                                         keyType: inspected.keyType,
                                         fingerprint: inspected.fingerprint)
        Task {
            let accepted = await decide(presented)
            if accepted {
                validationCompletePromise.succeed(())
            } else {
                validationCompletePromise.fail(HostKeyError.rejected)
            }
        }
    }
}

/// NIOSSH does not publicly expose a host key's bytes, so we reflect into the
/// internal backing key to recover the underlying CryptoKit/swift-crypto public
/// key and build the canonical OpenSSH wire encoding for fingerprinting.
/// Reflection is fragile by nature; every path degrades gracefully to a nil
/// fingerprint rather than crashing.
enum HostKeyInspector {
    static func inspect(_ key: NIOSSHPublicKey) -> (keyType: String, fingerprint: String?) {
        guard let blob = wireEncoding(of: key) else {
            return ("unknown", nil)
        }
        return (blob.type, KnownHostsStore.fingerprintSHA256(ofHostKey: blob.bytes))
    }

    private static func wireEncoding(of key: NIOSSHPublicKey) -> (type: String, bytes: Data)? {
        guard let backing = Mirror(reflecting: key).children
            .first(where: { $0.label == "backingKey" })?.value,
              let associated = Mirror(reflecting: backing).children.first?.value
        else { return nil }

        if let pub = associated as? Curve25519.Signing.PublicKey {
            return ("ssh-ed25519",
                    sshString("ssh-ed25519") + sshString(pub.rawRepresentation))
        }
        if let pub = associated as? P256.Signing.PublicKey {
            return ("ecdsa-sha2-nistp256",
                    sshString("ecdsa-sha2-nistp256") + sshString("nistp256")
                        + sshString(pub.x963Representation))
        }
        if let pub = associated as? P384.Signing.PublicKey {
            return ("ecdsa-sha2-nistp384",
                    sshString("ecdsa-sha2-nistp384") + sshString("nistp384")
                        + sshString(pub.x963Representation))
        }
        if let pub = associated as? P521.Signing.PublicKey {
            return ("ecdsa-sha2-nistp521",
                    sshString("ecdsa-sha2-nistp521") + sshString("nistp521")
                        + sshString(pub.x963Representation))
        }
        // Anything registered through SSHAlgorithms — today that is ssh-rsa,
        // whose rawRepresentation is already the wire body (mpint e, mpint n).
        // Without this an RSA server's key reaches the trust prompt as
        // "unknown" with no fingerprint, which is exactly the moment the user
        // needs to be able to check it.
        if let pub = associated as? NIOSSHPublicKeyProtocol {
            let type = Swift.type(of: pub).publicKeyPrefix
            return (type, sshString(type) + pub.rawRepresentation)
        }
        return nil
    }

    private static func sshString(_ s: String) -> Data { sshString(Data(s.utf8)) }

    private static func sshString(_ data: Data) -> Data {
        var out = Data()
        var len = UInt32(data.count).bigEndian
        withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
        out.append(data)
        return out
    }
}
