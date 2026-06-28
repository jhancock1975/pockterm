import Foundation
import SwiftData

/// Owns the app-wide SwiftData container and the production secret store.
@MainActor
final class AppContainer {
    let modelContainer: ModelContainer
    let secretStore: SecretStore

    init() {
        modelContainer = try! ModelContainer(
            for: Host.self, Identity.self, SSHKeyRecord.self, KnownHostRecord.self,
            HostGroup.self, Snippet.self)
        secretStore = KeychainSecretStore()
    }
}
