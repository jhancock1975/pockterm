import Foundation
import SwiftData

/// Owns the app-wide SwiftData container and the production secret store.
@MainActor
final class AppContainer {
    let modelContainer: ModelContainer
    let secretStore: SecretStore
    let sessions: SessionManager
    let forwards: ForwardRunner
    let modelRefresher: ModelCatalogRefresher

    init() {
        let container = try! ModelContainer(
            for: Host.self, Identity.self, SSHKeyRecord.self, KnownHostRecord.self,
            HostGroup.self, Snippet.self, PortForward.self, CommandHistory.self,
            AISettings.self, ConnectionSettings.self, AssistantMessageRecord.self)
        let store = KeychainSecretStore()
        modelContainer = container
        secretStore = store
        sessions = SessionManager(secretStore: store, modelContext: container.mainContext)
        forwards = ForwardRunner(secretStore: store, modelContext: container.mainContext)
        modelRefresher = ModelCatalogRefresher(secretStore: store)
    }
}
