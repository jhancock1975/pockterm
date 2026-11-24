import SwiftUI
import SwiftData
import LocalAuthentication

struct KeysListView: View {
    let secretStore: SecretStore
    @Environment(\.modelContext) private var ctx
    @Query(sort: \SSHKeyRecord.label) private var keys: [SSHKeyRecord]
    @State private var newKeyLabel = ""
    @State private var showGenerate = false
    @State private var showImport = false
    @State private var showGenerateEnclave = false
    @State private var enclaveError: String?

    var body: some View {
        NavigationStack {
            Group {
                if keys.isEmpty {
                    ContentUnavailableView("No Keys", systemImage: "key.fill",
                                           description: Text("Tap + to generate an Ed25519 key, or import one you already have."))
                } else {
                    List {
                        ForEach(keys) { key in
                            NavigationLink {
                                KeyDetailView(key: key)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(key.label).font(.headline)
                                    Group {
                                        if key.isSecureEnclave {
                                            Text("\(key.keyType) · Secure Enclave")
                                        } else {
                                            Text(key.keyType)
                                        }
                                    }
                                    .font(.caption).foregroundStyle(.secondary)
                                    Text(key.publicKeyOpenSSH)
                                        .font(.system(.caption2, design: .monospaced))
                                        .lineLimit(1).truncationMode(.middle)
                                        .foregroundStyle(.tertiary)
                                }
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
                    if EnclaveKey.isAvailable {
                        Button("Generate Secure Enclave Key…") { showGenerateEnclave = true }
                    }
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
            .alert("Generate Secure Enclave Key", isPresented: $showGenerateEnclave) {
                TextField("Label", text: $newKeyLabel)
                Button("Generate") { Task { await generateEnclave() } }
                Button("Cancel", role: .cancel) { newKeyLabel = "" }
            } message: {
                Text("The private key is made inside this iPhone's Secure Enclave and can never leave it. Every connection asks for Face ID.")
            }
            .alert("Couldn't Make the Key", isPresented: Binding(
                get: { enclaveError != nil }, set: { if !$0 { enclaveError = nil } })) {
                Button("OK", role: .cancel) { enclaveError = nil }
            } message: {
                Text(enclaveError ?? "")
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

    /// Makes the key, then has Face ID confirm the enclave will sign with it
    /// before saving, so a key that can't be used never reaches a server's
    /// authorized_keys.
    private func generateEnclave() async {
        let label = newKeyLabel.isEmpty ? "key-\(Int(Date().timeIntervalSince1970))" : newKeyLabel
        newKeyLabel = ""
        do {
            guard LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else {
                throw EnclaveKeyError.biometryUnavailable
            }
            let gen = try EnclaveKey.generate(comment: "\(label)@pockterm")
            guard let blob = EnclaveKey.blob(fromPEM: gen.privateKeyPEM) else { return }
            _ = try await EnclaveKey.unlock(
                blob: blob, reason: String(localized: "Confirm it's you to finish making the key."))
            let rec = SSHKeyRecord(label: label, keyType: gen.keyType,
                                   publicKeyOpenSSH: gen.publicKeyOpenSSH, isSecureEnclave: true)
            try secretStore.setString(gen.privateKeyPEM, for: rec.id.uuidString)
            ctx.insert(rec)
            try? ctx.save()
        } catch EnclaveKeyError.cancelled {
            // Nothing saved; the user changed their mind.
        } catch {
            enclaveError = error.localizedDescription
        }
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
