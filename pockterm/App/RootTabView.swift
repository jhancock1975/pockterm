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
        // The system's mini-player slot: sits above the tab bar rather than
        // covering it, the way Music parks a playing track.
        .tabViewBottomAccessory {
            if sessions.isMinimized, let active = sessions.active {
                MinimizedSessionBar(manager: sessions, active: active)
            }
        }
        .fullScreenCover(isPresented: presentingSessions) {
            SessionTabsView(manager: sessions)
        }
    }

    /// Dismissing the cover minimizes rather than disconnecting; sessions stay
    /// connected and are restored from the accessory bar or the Hosts list.
    /// Sessions end only via the explicit close buttons in the tab strip.
    private var presentingSessions: Binding<Bool> {
        Binding(get: { sessions.isTerminalPresented },
                set: { if !$0 { sessions.minimize() } })
    }
}

/// The minimized terminal, parked above the tab bar. Tap to return to the
/// active session. The accessory supplies its own glass background.
private struct MinimizedSessionBar: View {
    let manager: SessionManager
    let active: TerminalSession

    var body: some View {
        Button { manager.reveal() } label: {
            HStack(spacing: 10) {
                Image(systemName: "terminal.fill")
                VStack(alignment: .leading, spacing: 1) {
                    Text(active.title).font(.subheadline.weight(.semibold))
                    if manager.sessions.count > 1 {
                        Text("\(manager.sessions.count) sessions")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.up").font(.footnote).foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .padding(.horizontal, 14)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .tint(.primary)
        .accessibilityLabel("Resume session \(active.title)")
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
