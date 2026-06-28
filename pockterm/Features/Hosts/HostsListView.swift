import SwiftUI
import SwiftData

struct HostsListView: View {
    let secretStore: SecretStore
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Host.label) private var hosts: [Host]
    @State private var editing: Host?
    @State private var connecting: Host?

    var body: some View {
        NavigationStack {
            Group {
                if hosts.isEmpty {
                    ContentUnavailableView("No Hosts", systemImage: "server.rack",
                                           description: Text("Tap + to add a host."))
                } else {
                    List {
                        ForEach(hosts) { host in
                            Button { connecting = host } label: { row(host) }
                                .swipeActions {
                                    Button("Edit") { editing = host }.tint(.blue)
                                    Button("Delete", role: .destructive) { ctx.delete(host) }
                                }
                        }
                    }
                }
            }
            .navigationTitle("Hosts")
            .toolbar {
                Button { editing = Host(label: "", address: "") } label: { Image(systemName: "plus") }
            }
            .sheet(item: $editing) { host in
                HostEditorView(secretStore: secretStore, host: host)
            }
            .fullScreenCover(item: $connecting) { host in
                TerminalSessionView(secretStore: secretStore, host: host)
            }
        }
    }

    private func row(_ host: Host) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(host.label).font(.headline)
            Text("\(host.identity?.username ?? "—")@\(host.address):\(host.port)")
                .font(.subheadline).foregroundStyle(.secondary)
        }
    }
}
