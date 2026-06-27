import Foundation

/// Abstraction over secret storage so the credential layer can be unit-tested
/// without the real Keychain (which is unavailable in SwiftPM-style iOS tests).
protocol SecretStore {
    func set(_ data: Data, for key: String) throws
    func get(_ key: String) throws -> Data?
    func delete(_ key: String) throws
}

extension SecretStore {
    func setString(_ s: String, for key: String) throws { try set(Data(s.utf8), for: key) }
    func getString(_ key: String) throws -> String? {
        try get(key).flatMap { String(data: $0, encoding: .utf8) }
    }
}
