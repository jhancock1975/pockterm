import Foundation
import Citadel
import Crypto

enum SSHAuth {
    case password(String)
    /// Raw 32-byte Ed25519 seed (as produced by `KeyManager`).
    case ed25519Seed(Data)
}

struct SSHCredentials {
    let host: String
    let port: Int
    let username: String
    let auth: SSHAuth
}

extension SSHCredentials {
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
        }
    }
}
