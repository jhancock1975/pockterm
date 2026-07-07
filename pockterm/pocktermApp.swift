import SwiftUI
import SwiftData

@main
struct pocktermApp: App {
    @State private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView(secretStore: container.secretStore, sessions: container.sessions,
                        forwards: container.forwards)
                .modelContainer(container.modelContainer)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { container.modelRefresher.refreshStaleCatalogs() }
                }
        }
    }
}
