import Foundation

/// Test double for `SecretStore`. Never used in production.
final class InMemorySecretStore: SecretStore {
    private var storage: [String: Data] = [:]
    private let lock = NSLock()
    func set(_ data: Data, for key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = data
    }
    func get(_ key: String) throws -> Data? {
        lock.lock(); defer { lock.unlock() }
        return storage[key]
    }
    func delete(_ key: String) throws {
        lock.lock(); defer { lock.unlock() }
        storage[key] = nil
    }
}
