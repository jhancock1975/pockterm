import SwiftUI

/// Top-level tab navigation.
struct RootTabView: View {
    let secretStore: SecretStore
    let sessions: SessionManager
    let forwards: ForwardRunner

    var body: some View {
        TabView {
            HostsListView(secretStore: secretStore, sessions: sessions)
                .tabItem { Label("Hosts", systemImage: "server.rack") }

            SnippetsListView()
                .tabItem { Label("Snippets", systemImage: "text.badge.plus") }

            KeysListView(secretStore: secretStore)
                .tabItem { Label("Keychain", systemImage: "key.fill") }

            ForwardsListView(runner: forwards)
                .tabItem { Label("Forwarding", systemImage: "arrow.left.arrow.right") }

            SettingsHomeView(secretStore: secretStore)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .fullScreenCover(isPresented: presentingSessions) {
            SessionTabsView(manager: sessions)
        }
    }

    private var presentingSessions: Binding<Bool> {
        Binding(get: { !sessions.sessions.isEmpty },
                set: { if !$0 { sessions.closeAll() } })
    }
}

private struct SettingsHomeView: View {
    let secretStore: SecretStore
    var body: some View {
        NavigationStack {
            List {
                NavigationLink {
                    AISettingsView(secretStore: secretStore)
                } label: {
                    Label("AI Assistant", systemImage: "sparkles")
                }
                NavigationLink {
                    KeyBarSettingsView()
                } label: {
                    Label("Key Bar", systemImage: "keyboard")
                }
            }
            .navigationTitle("Settings")
        }
    }
}
