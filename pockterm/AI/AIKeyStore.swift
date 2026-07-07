import Foundation

/// Reads and writes per-provider API keys through the Keychain-backed
/// `SecretStore`; keys never touch SwiftData or plaintext storage.
struct AIKeyStore {
    let secretStore: SecretStore

    func setKey(_ key: String, for provider: AIProvider) throws {
        // Pasted keys often carry a trailing newline; stored verbatim it would
        // corrupt the HTTP auth header and every request would be rejected.
        let cleaned = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try secretStore.setString(cleaned, for: provider.keychainKeyID)
    }

    func key(for provider: AIProvider) throws -> String? {
        try secretStore.getString(provider.keychainKeyID)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func removeKey(for provider: AIProvider) throws {
        try secretStore.delete(provider.keychainKeyID)
    }
}
