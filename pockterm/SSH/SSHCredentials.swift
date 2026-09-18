import Foundation
import Citadel
import Crypto

nonisolated enum SSHAuth {
    case password(String)
    /// Raw 32-byte Ed25519 seed (as produced by `KeyManager`).
    case ed25519Seed(Data)
    /// An OpenSSH private key the user imported, exactly as they pasted it,
    /// with the passphrase it needs (if any). Kept in its original form rather
    /// than converted on import: Citadel can parse the container but cannot
    /// write one, so re-encoding would mean writing a serialiser to hold a key
    /// we can already read.
    case openSSHKey(pem: String, passphrase: String?)
}

nonisolated struct SSHCredentials {
    let host: String
    let port: Int
    let username: String
    let auth: SSHAuth
}

nonisolated extension SSHCredentials {
    /// The Citadel authentication method these credentials describe. Shared by
    /// every connection owner (shell, SFTP, port forwards) so they cannot
    /// disagree about how a stored secret becomes an auth method.
    func authenticationMethod() throws -> SSHAuthenticationMethod {
        switch auth {
        case .password(let password):
            return .passwordBased(username: username, password: password)
        case .ed25519Seed(let seed):
            guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else {
                throw SSHEngineError.invalidKey
            }
            return .ed25519(username: username, privateKey: key)
        case .openSSHKey(let pem, let passphrase):
            let secret = passphrase.flatMap { $0.isEmpty ? nil : Data($0.utf8) }
            guard let type = try? SSHKeyDetection.detectPrivateKeyType(from: pem) else {
                throw SSHEngineError.invalidKey
            }
            switch type {
            case .ed25519:
                guard let key = try? Curve25519.Signing.PrivateKey(sshEd25519: pem, decryptionKey: secret) else {
                    throw SSHEngineError.invalidKey
                }
                return .ed25519(username: username, privateKey: key)
            case .rsa:
                guard let key = try? Insecure.RSA.PrivateKey(sshRsa: pem, decryptionKey: secret) else {
                    throw SSHEngineError.invalidKey
                }
                return .rsa(username: username, privateKey: key)
            default:
                throw SSHEngineError.invalidKey
            }
        }
    }
}
