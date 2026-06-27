import Testing
import Foundation
@testable import pockterm

@Test func inMemoryStoreRoundTrips() throws {
    let store: SecretStore = InMemorySecretStore()
    let secret = Data("hunter2".utf8)
    try store.set(secret, for: "id-1")
    #expect(try store.get("id-1") == secret)
    try store.delete("id-1")
    #expect(try store.get("id-1") == nil)
}

@Test func inMemoryStoreStringHelpers() throws {
    let store: SecretStore = InMemorySecretStore()
    try store.setString("s3cr3t", for: "k")
    #expect(try store.getString("k") == "s3cr3t")
}
