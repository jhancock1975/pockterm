import Foundation
import CryptoKit
import LocalAuthentication
import NIOCore
import NIOSSH

/// SSH keys made inside the Secure Enclave (issue #39). The private key never
/// exists outside the enclave: what is stored is CryptoKit's
/// `dataRepresentation`, a blob only this device's enclave can use, wrapped in
/// pockterm's own markers the way `KeyManager` wraps an Ed25519 seed. Every
/// use needs Face ID (or Touch ID), and the key stops working if the enrolled
/// faces or fingers change.
nonisolated enum EnclaveKey {
    static let beginMarker = "-----BEGIN POCKTERM SECURE ENCLAVE P256 KEY-----"
    static let endMarker = "-----END POCKTERM SECURE ENCLAVE P256 KEY-----"
    static let keyType = "ecdsa-sha2-nistp256"

    /// False on the simulator, which has no enclave.
    static var isAvailable: Bool { SecureEnclave.isAvailable }

    /// `requireBiometry` is always true in the app. It exists so the signing
    /// path can be exercised on a Mac with no one there to touch the sensor.
    static func accessControl(requireBiometry: Bool = true) throws -> SecAccessControl {
        var flags: SecAccessControlCreateFlags = [.privateKeyUsage]
        if requireBiometry { flags.insert(.biometryCurrentSet) }
        var error: Unmanaged<CFError>?
        guard let control = SecAccessControlCreateWithFlags(
            nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, &error) else {
            throw error!.takeRetainedValue() as Error
        }
        return control
    }

    static func generate(comment: String, requireBiometry: Bool = true) throws -> GeneratedKey {
        let key = try SecureEnclave.P256.Signing.PrivateKey(
            accessControl: accessControl(requireBiometry: requireBiometry))
        return GeneratedKey(privateKeyPEM: pem(fromBlob: key.dataRepresentation),
                            publicKeyOpenSSH: openSSHPublicKey(key.publicKey, comment: comment),
                            keyType: keyType)
    }

    static func pem(fromBlob blob: Data) -> String {
        "\(beginMarker)\n\(blob.base64EncodedString())\n\(endMarker)\n"
    }

    /// The enclave blob inside one of pockterm's enclave-key wrappers, or nil
    /// for anything else (an Ed25519 seed, an imported OpenSSH key).
    static func blob(fromPEM pem: String) -> Data? {
        guard pem.hasPrefix(beginMarker) else { return nil }
        let body = pem.split(separator: "\n").filter { !$0.hasPrefix("-----") }.joined()
        return Data(base64Encoded: body)
    }

    /// The `authorized_keys` line: `ecdsa-sha2-nistp256`, then the curve name
    /// and the uncompressed point, each length-prefixed (RFC 5656 §3.1).
    static func openSSHPublicKey(_ key: P256.Signing.PublicKey, comment: String) -> String {
        func lengthPrefixed(_ d: Data) -> Data {
            var out = Data()
            var len = UInt32(d.count).bigEndian
            withUnsafeBytes(of: &len) { out.append(contentsOf: $0) }
            out.append(d)
            return out
        }
        var blob = Data()
        blob.append(lengthPrefixed(Data(keyType.utf8)))
        blob.append(lengthPrefixed(Data("nistp256".utf8)))
        blob.append(lengthPrefixed(key.x963Representation))
        return "\(keyType) \(blob.base64EncodedString()) \(comment)"
    }

    /// Asks for Face ID, then hands back the key ready to sign without asking
    /// again. Doing this before connecting, rather than letting the first
    /// signature ask, keeps the prompt off the SSH handshake, which would
    /// otherwise wait on it inside its own login timeout.
    ///
    /// A key that can't sign after a successful Face ID check has been
    /// invalidated: the enrolled biometrics changed, or the blob came from
    /// another device. That is reported as `.unusable`, not as a failed login.
    static func unlock(blob: Data, reason: String) async throws -> SecureEnclave.P256.Signing.PrivateKey {
        let context = LAContext()
        do {
            _ = try await context.evaluateAccessControl(
                accessControl(), operation: .useKeySign, localizedReason: reason)
        } catch let error as LAError {
            switch error.code {
            case .userCancel, .appCancel, .systemCancel, .userFallback:
                throw EnclaveKeyError.cancelled
            case .biometryNotEnrolled, .biometryNotAvailable, .passcodeNotSet:
                throw EnclaveKeyError.biometryUnavailable
            default:
                throw error
            }
        }
        do {
            let key = try SecureEnclave.P256.Signing.PrivateKey(
                dataRepresentation: blob, authenticationContext: context)
            _ = try key.signature(for: Data("pockterm".utf8))
            return key
        } catch {
            throw EnclaveKeyError.unusable
        }
    }
}

nonisolated enum EnclaveKeyError: Error, LocalizedError, Equatable {
    /// Face ID was cancelled. Not retried: asking again would only repeat the prompt.
    case cancelled
    /// No Face ID or Touch ID enrolled, so an enclave key can't be made or used.
    case biometryUnavailable
    /// The enclave refuses the key even after Face ID passed.
    case unusable

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return String(localized: "Face ID was cancelled, so the key wasn't used.")
        case .biometryUnavailable:
            return String(localized: "Secure Enclave keys need Face ID or Touch ID. Set it up in Settings first.")
        case .unusable:
            return String(localized: "This Secure Enclave key can't be used any more. It is tied to this iPhone and to the Face ID set up when it was made, and one of them has changed. Generate a new key and add it to the server.")
        }
    }
}

/// Offers one enclave key for public-key authentication. Citadel's own
/// constructors take only exportable key types, so the key goes in through
/// `SSHAuthenticationMethod.custom`.
nonisolated final class EnclaveKeyAuthentication: NIOSSHClientUserAuthenticationDelegate, @unchecked Sendable {
    private let username: String
    private let key: NIOSSHPrivateKey
    private var offered = false

    init(username: String, key: SecureEnclave.P256.Signing.PrivateKey) {
        self.username = username
        self.key = NIOSSHPrivateKey(secureEnclaveP256Key: key)
    }

    func nextAuthenticationType(availableMethods: NIOSSHAvailableUserAuthenticationMethods,
                                nextChallengePromise: EventLoopPromise<NIOSSHUserAuthenticationOffer?>) {
        guard !offered, availableMethods.contains(.publicKey) else {
            nextChallengePromise.succeed(nil)
            return
        }
        offered = true
        nextChallengePromise.succeed(NIOSSHUserAuthenticationOffer(
            username: username, serviceName: "", offer: .privateKey(.init(privateKey: key))))
    }
}
