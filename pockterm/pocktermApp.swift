import SwiftUI
import SwiftData

@main
struct pocktermApp: App {
    @State private var container = AppContainer()

    var body: some Scene {
        WindowGroup {
            RootTabView(secretStore: container.secretStore, sessions: container.sessions)
                .modelContainer(container.modelContainer)
        }
    }
}
