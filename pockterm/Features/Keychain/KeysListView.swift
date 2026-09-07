import SwiftUI
import SwiftData

struct KeysListView: View {
    let secretStore: SecretStore
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SSHKeyRecord.label) private var keys: [SSHKeyRecord]
    @State private var newKeyLabel = ""
    @State private var showGenerate = false
    @State private var showImport = false

    var body: some View {
        NavigationStack {
            Group {
                if keys.isEmpty {
                    ContentUnavailableView("No Keys", systemImage: "key.fill",
                                           description: Text("Tap + to generate an Ed25519 key, or import one you already have."))
                } else {
                    List {
                        ForEach(keys) { key in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key.label).font(.headline)
                                Text(key.keyType).font(.caption).foregroundStyle(.secondary)
                                Text(key.publicKeyOpenSSH)
                                    .font(.system(.caption2, design: .monospaced))
                                    .lineLimit(1).truncationMode(.middle)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Keychain")
            .toolbar {
                Menu {
                    Button("Generate Ed25519 Key…") { showGenerate = true }
                    Button("Import Existing Key…") { showImport = true }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel(Text("Add Key"))
            }
            .sheet(isPresented: $showImport) {
                ImportKeyView(secretStore: secretStore)
            }
            .alert("Generate Ed25519 Key", isPresented: $showGenerate) {
                TextField("Label", text: $newKeyLabel)
                Button("Generate") { generate() }
                Button("Cancel", role: .cancel) { newKeyLabel = "" }
            } message: {
                Text("Creates a new key pair stored securely in the Keychain.")
            }
        }
    }

    private func generate() {
        let label = newKeyLabel.isEmpty ? "key-\(Int(Date().timeIntervalSince1970))" : newKeyLabel
        let gen = KeyManager.generateEd25519(comment: "\(label)@pockterm")
        let rec = SSHKeyRecord(label: label, keyType: gen.keyType, publicKeyOpenSSH: gen.publicKeyOpenSSH)
        try? secretStore.setString(gen.privateKeyPEM, for: rec.id.uuidString)
        ctx.insert(rec)
        try? ctx.save()
        newKeyLabel = ""
    }

    private func delete(_ offsets: IndexSet) {
        for i in offsets {
            let key = keys[i]
            try? secretStore.delete(key.id.uuidString)
            // Imported keys may have a passphrase stored beside them; leaving
            // it behind would keep a secret for a key that no longer exists.
            try? secretStore.delete(PrivateKeyImport.passphraseKey(for: key.id))
            ctx.delete(key)
        }
    }
}
