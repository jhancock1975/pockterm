import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Imports hosts from a pasted or file-selected `~/.ssh/config`. Shows a
/// preview with per-row toggles before committing. For each distinct `User`,
/// a password identity is created (with an empty secret for the user to fill).
struct ImportConfigView: View {
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    let secretStore: SecretStore

    @State private var text = ""
    @State private var included: Set<String> = []
    @State private var showingFileImporter = false

    private var parsed: [ParsedHost] { SSHConfigParser.parse(text) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Paste ~/.ssh/config") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .font(.system(.callout, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Choose File…") { showingFileImporter = true }
                }

                if !parsed.isEmpty {
                    Section("Hosts to import (\(included.count) selected)") {
                        ForEach(parsed, id: \.alias) { host in
                            Toggle(isOn: binding(for: host.alias)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(host.alias).font(.headline)
                                    Text("\(host.user ?? "—")@\(host.hostName ?? host.alias):\((host.port ?? 22).technicalDigits)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Import Hosts")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: text) { _, _ in included = Set(parsed.map(\.alias)) }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importSelected() }.disabled(included.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(isPresented: $showingFileImporter,
                          allowedContentTypes: [.data, .text, .plainText, .item]) { result in
                if case .success(let url) = result { loadFile(url) }
            }
        }
    }

    private func binding(for alias: String) -> Binding<Bool> {
        Binding(get: { included.contains(alias) },
                set: { isOn in
                    if isOn { included.insert(alias) } else { included.remove(alias) }
                })
    }

    private func loadFile(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func importSelected() {
        var identitiesByUser: [String: Identity] = [:]
        let existing = (try? ctx.fetch(FetchDescriptor<Identity>())) ?? []
        for id in existing { identitiesByUser[id.username] = id }

        for parsedHost in parsed where included.contains(parsedHost.alias) {
            var identity: Identity?
            if let user = parsedHost.user {
                if let found = identitiesByUser[user] {
                    identity = found
                } else {
                    let new = Identity(label: user, username: user, authMethod: .password)
                    try? secretStore.setString("", for: new.id.uuidString)
                    ctx.insert(new)
                    identitiesByUser[user] = new
                    identity = new
                }
            }
            let host = Host(label: parsedHost.alias,
                            address: parsedHost.hostName ?? parsedHost.alias,
                            port: parsedHost.port ?? 22,
                            identity: identity)
            ctx.insert(host)
        }
        try? ctx.save()
        dismiss()
    }
}
