import SwiftUI
import SwiftData

struct HostsListView: View {
    let secretStore: SecretStore
    let sessions: SessionManager
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Host.label) private var hosts: [Host]
    @State private var editing: Host?
    @State private var importing = false
    @State private var managingGroups = false
    @State private var filesHost: Host?
    @State private var searchText = ""

    private var filtered: [Host] {
        guard !searchText.isEmpty else { return hosts }
        let q = searchText.lowercased()
        return hosts.filter { $0.label.lowercased().contains(q) || $0.address.lowercased().contains(q) }
    }

    private var favorites: [Host] {
        searchText.isEmpty ? hosts.filter(\.isFavorite) : []
    }

    private var recents: [Host] {
        guard searchText.isEmpty else { return [] }
        return hosts
            .filter { $0.lastConnectedAt != nil }
            .sorted { ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast) }
            .prefix(5)
            .map { $0 }
    }

    /// Hosts bucketed by group name, with ungrouped hosts last.
    private var sections: [(title: String, hosts: [Host])] {
        let grouped = Dictionary(grouping: filtered) { $0.group?.name }
        let named = grouped
            .compactMap { key, value -> (String, [Host])? in
                guard let key else { return nil }
                return (key, value)
            }
            .sorted { $0.0 < $1.0 }
        var result = named.map { (title: $0.0, hosts: $0.1) }
        if let ungrouped = grouped[String?.none] ?? nil, !ungrouped.isEmpty {
            result.append((title: "Ungrouped", hosts: ungrouped))
        }
        return result
    }

    var body: some View {
        NavigationStack {
            Group {
                if hosts.isEmpty {
                    ContentUnavailableView("No Hosts", systemImage: "server.rack",
                                           description: Text("Tap + to add a host."))
                } else {
                    List {
                        if !favorites.isEmpty {
                            Section("Favorites") {
                                ForEach(favorites) { hostRow($0) }
                            }
                        }
                        if !recents.isEmpty {
                            Section("Recents") {
                                ForEach(recents) { hostRow($0) }
                            }
                        }
                        ForEach(sections, id: \.title) { section in
                            Section(section.title) {
                                ForEach(section.hosts) { hostRow($0) }
                            }
                        }
                    }
                }
            }
            .searchable(text: $searchText, prompt: "Search hosts")
            .navigationTitle("Hosts")
            .toolbar {
                Menu {
                    Button { editing = Host(label: "", address: "") } label: {
                        Label("New Host", systemImage: "plus")
                    }
                    Button { managingGroups = true } label: {
                        Label("Manage Groups", systemImage: "folder")
                    }
                    Button { importing = true } label: {
                        Label("Import from ssh_config", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
            .sheet(item: $editing) { host in
                HostEditorView(secretStore: secretStore, host: host)
            }
            .sheet(isPresented: $importing) {
                ImportConfigView(secretStore: secretStore)
            }
            .sheet(isPresented: $managingGroups) {
                GroupsListView()
            }
            .sheet(item: $filesHost) { host in
                FilesBrowserView(host: host, secretStore: secretStore, modelContext: ctx)
            }
        }
    }

    private func hostRow(_ host: Host) -> some View {
        Button { sessions.open(host) } label: { row(host) }
            .swipeActions(edge: .leading) {
                Button("Files") { filesHost = host }.tint(.indigo)
            }
            .swipeActions {
                Button("Edit") { editing = host }.tint(.blue)
                Button(host.isFavorite ? "Unstar" : "Star") { host.isFavorite.toggle() }.tint(.yellow)
                Button("Delete", role: .destructive) { ctx.delete(host) }
            }
    }

    private func row(_ host: Host) -> some View {
        let eff = EffectiveHostSettings.resolve(host: host)
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(host.label).font(.headline)
                Text("\(eff.identity?.username ?? "—")@\(host.address):\(eff.port)")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if host.isFavorite {
                Image(systemName: "star.fill").foregroundStyle(.yellow).font(.caption)
            }
        }
    }
}
