import Foundation

/// Reads and writes per-provider API keys through the Keychain-backed
/// `SecretStore`; keys never touch SwiftData or plaintext storage.
struct AIKeyStore {
    let secretStore: SecretStore

    func setKey(_ key: String, for provider: AIProvider) throws {
        try secretStore.setString(key, for: provider.keychainKeyID)
    }

    func key(for provider: AIProvider) throws -> String? {
        try secretStore.getString(provider.keychainKeyID)
    }

    func removeKey(for provider: AIProvider) throws {
        try secretStore.delete(provider.keychainKeyID)
    }
}
