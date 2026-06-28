import SwiftUI

/// Top-level Termius-style tab navigation. Snippets, Port Forwarding, and
/// Settings are placeholders filled in by later phases.
struct RootTabView: View {
    let secretStore: SecretStore

    var body: some View {
        TabView {
            HostsListView(secretStore: secretStore)
                .tabItem { Label("Hosts", systemImage: "server.rack") }

            SnippetsListView()
                .tabItem { Label("Snippets", systemImage: "text.badge.plus") }

            KeysListView(secretStore: secretStore)
                .tabItem { Label("Keychain", systemImage: "key.fill") }

            PlaceholderTab(title: "Port Forwarding", systemImage: "arrow.left.arrow.right")
                .tabItem { Label("Forwarding", systemImage: "arrow.left.arrow.right") }

            PlaceholderTab(title: "Settings", systemImage: "gearshape")
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

private struct PlaceholderTab: View {
    let title: String
    let systemImage: String
    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: systemImage,
                                   description: Text("Coming in a later phase."))
                .navigationTitle(title)
        }
    }
}
