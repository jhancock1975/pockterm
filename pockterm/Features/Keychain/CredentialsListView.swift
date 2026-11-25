import SwiftUI
import SwiftData

/// Every saved set of credentials, under Hosts. Tap one to edit it; swipe or
/// long-press for Edit and Delete. Before this, credentials could only be made
/// from a host's editor and never changed, so a wrong username meant making
/// new ones and leaving the old ones behind for good.
struct CredentialsListView: View {
    let secretStore: SecretStore
    var searchText: String = ""
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Identity.label) private var identities: [Identity]
    @Query private var hosts: [Host]
    @Query private var groups: [HostGroup]
    @Query private var keys: [SSHKeyRecord]
    @State private var editing: Identity?
    @State private var deleting: Identity?

    private var filtered: [Identity] {
        guard !searchText.isEmpty else { return identities }
        let q = searchText.lowercased()
        return identities.filter { $0.label.lowercased().contains(q) || $0.username.lowercased().contains(q) }
    }

    var body: some View {
        Group {
            if identities.isEmpty {
                ContentUnavailableView("No Credentials", systemImage: "person.badge.key",
                                       description: Text("Tap + to add a username with a password or a key."))
            } else {
                List {
                    ForEach(filtered) { identity in
                        Button { editing = identity } label: { row(identity) }
                            .foregroundStyle(.primary)
                            .swipeActions {
                                Button("Edit") { editing = identity }.tint(.blue)
                                Button("Delete", role: .destructive) { deleting = identity }
                            }
                            .contextMenu {
                                Button { editing = identity } label: { Label("Edit", systemImage: "pencil") }
                                Button(role: .destructive) { deleting = identity } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .sheet(item: $editing) { identity in
            NavigationStack { IdentityEditorView(secretStore: secretStore, identity: identity, showsCancel: true) }
        }
        .confirmationDialog(deleteTitle, isPresented: isDeleting, titleVisibility: .visible,
                            presenting: deleting) { identity in
            Button("Delete", role: .destructive) { delete(identity) }
        } message: { identity in
            let users = usedBy(identity)
            if !users.isEmpty {
                Text("Used by \(users.joined(separator: ", ")). They will have no credentials until you choose others.")
            }
        }
    }

    private func row(_ identity: Identity) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(identity.label).font(.headline)
            Text(detail(identity)).font(.caption).foregroundStyle(.secondary)
            let users = usedBy(identity)
            if !users.isEmpty {
                Text("Used by \(users.joined(separator: ", "))")
                    .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func detail(_ identity: Identity) -> String {
        switch identity.authMethod {
        case .password:
            return String(localized: "\(identity.username) · Password")
        case .key:
            let key = keys.first { $0.id == identity.keyRef }?.label ?? String(localized: "missing key")
            return String(localized: "\(identity.username) · Key: \(key)")
        }
    }

    /// Hosts and groups that sign in with these credentials, by name.
    private func usedBy(_ identity: Identity) -> [String] {
        let id = identity.id
        let hostNames = hosts.filter { $0.identity?.id == id }.map(\.label).sorted()
        let groupNames = groups.filter { $0.defaultIdentity?.id == id }.map(\.name).sorted()
        return hostNames + groupNames
    }

    private var deleteTitle: String {
        String(localized: "Delete \u{201C}\(deleting?.label ?? "")\u{201D}?")
    }

    private var isDeleting: Binding<Bool> {
        Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })
    }

    private func delete(_ identity: Identity) {
        // Cleared by hand rather than trusting a delete rule: these
        // relationships declare no inverse.
        let id = identity.id
        for host in hosts where host.identity?.id == id { host.identity = nil }
        for group in groups where group.defaultIdentity?.id == id { group.defaultIdentity = nil }
        try? secretStore.delete(identity.id.uuidString)
        ctx.delete(identity)
        try? ctx.save()
        deleting = nil
    }
}
