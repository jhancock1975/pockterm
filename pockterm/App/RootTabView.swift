import SwiftUI

/// Destinations pushed onto the Settings tab's navigation stack, so other
/// parts of the app (e.g. the inactivity-disconnect screen) can deep-link in.
enum SettingsRoute: Hashable {
    case connection
}

/// Top-level tab navigation.
struct RootTabView: View {
    let secretStore: SecretStore
    let sessions: SessionManager
    let forwards: ForwardRunner

    @State private var selectedTab = 0
    @State private var settingsPath = NavigationPath()

    var body: some View {
        TabView(selection: $selectedTab) {
            HostsListView(secretStore: secretStore, sessions: sessions)
                .tabItem { Label("Hosts", systemImage: "server.rack") }
                .tag(0)

            SnippetsListView()
                .tabItem { Label("Snippets", systemImage: "text.badge.plus") }
                .tag(1)

            KeysListView(secretStore: secretStore)
                .tabItem { Label("Keychain", systemImage: "key.fill") }
                .tag(2)

            ForwardsListView(runner: forwards)
                .tabItem { Label("Forwarding", systemImage: "arrow.left.arrow.right") }
                .tag(3)

            SettingsHomeView(secretStore: secretStore, path: $settingsPath)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(4)
        }
        // The system's mini-player slot: sits above the tab bar rather than
        // covering it, the way Music parks a playing track. Falls back to a
        // bottom safe-area inset on iOS < 26, where the accessory API and its
        // glass background don't exist.
        .minimizedSessionAccessory(sessions: sessions)
        .fullScreenCover(isPresented: presentingSessions) {
            SessionTabsView(manager: sessions)
        }
        .onChange(of: sessions.requestOpenConnectionSettings) { _, want in
            guard want else { return }
            selectedTab = 4                       // Settings tab
            settingsPath = NavigationPath()
            settingsPath.append(SettingsRoute.connection)
            sessions.requestOpenConnectionSettings = false
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

private extension View {
    /// Parks the minimized-session bar above the tab bar. Uses the iOS 26
    /// `tabViewBottomAccessory` slot (with its own glass background) where
    /// available, and falls back to a bottom safe-area inset on iOS < 26.
    @ViewBuilder
    func minimizedSessionAccessory(sessions: SessionManager) -> some View {
        if #available(iOS 26.0, *) {
            self.tabViewBottomAccessory {
                if sessions.isMinimized, let active = sessions.active {
                    MinimizedSessionBar(manager: sessions, active: active)
                }
            }
        } else {
            self.safeAreaInset(edge: .bottom) {
                if sessions.isMinimized, let active = sessions.active {
                    MinimizedSessionBar(manager: sessions, active: active)
                        .padding(.vertical, 8)
                        .background(.bar)
                }
            }
        }
    }
}

private struct SettingsHomeView: View {
    let secretStore: SecretStore
    @Binding var path: NavigationPath

    var body: some View {
        NavigationStack(path: $path) {
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
                NavigationLink {
                    ConnectionSettingsView()
                } label: {
                    Label("Connection", systemImage: "network")
                }
            }
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsRoute.self) { _ in
                ConnectionSettingsView()
            }
        }
    }
}
