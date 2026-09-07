import Foundation

/// Result of resolving a host's connection credentials.
enum CredentialResult {
    case success(SSHCredentials)
    case failure(String)
}

/// Shared connection helpers used by both the terminal and SFTP.
enum HostConnection {
    /// Resolves credentials for a host using effective (group-inherited)
    /// settings plus secrets from the store. Returns the credentials, or a
    /// user-facing error message.
    @MainActor
    static func credentials(for host: Host, secretStore: SecretStore) -> CredentialResult {
        let effective = EffectiveHostSettings.resolve(host: host)
        guard let identity = effective.identity else {
            return .failure("This host has no credentials. Edit the host and choose one.")
        }
        let auth: SSHAuth
        switch identity.authMethod {
        case .password:
            let password = (try? secretStore.getString(identity.id.uuidString)) ?? ""
            auth = .password(password ?? "")
        case .key:
            guard let keyId = identity.keyRef,
                  let pem = (try? secretStore.getString(keyId.uuidString)) ?? nil else {
                return .failure("The SSH key for these credentials is missing.")
            }
            // Generated keys are stored as a bare seed in pockterm's own
            // wrapper; imported ones keep the OpenSSH container they arrived
            // in, with any passphrase alongside them.
            if let seed = KeyManager.seed(fromPEM: pem) {
                auth = .ed25519Seed(seed)
            } else if pem.hasPrefix(PrivateKeyImport.openSSHBegin) {
                let passphrase = (try? secretStore.getString(PrivateKeyImport.passphraseKey(for: keyId))) ?? nil
                auth = .openSSHKey(pem: pem, passphrase: passphrase)
            } else {
                return .failure("The SSH key for these credentials could not be read.")
            }
        }
        return .success(SSHCredentials(host: host.address, port: effective.port,
                                       username: identity.username, auth: auth))
    }
}
