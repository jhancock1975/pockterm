import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Brings in an SSH key the user already has, rather than making them generate
/// a new one in the app and add it to every server by hand.
struct ImportKeyView: View {
    let secretStore: SecretStore
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var pastedKey = ""
    @State private var passphrase = ""
    /// Only shown once the key turns out to need one — asking for a passphrase
    /// up front implies every key has one.
    @State private var needsPassphrase = false
    @State private var errorMessage: String?
    @State private var showFileImporter = false
    @FocusState private var passphraseFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Label", text: $label)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("A name for this key in Pockterm. The key itself is unchanged.")
                }

                Section {
                    TextEditor(text: $pastedKey)
                        .font(.system(.caption2, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .frame(minHeight: 140)
                    Button("Choose File…") { showFileImporter = true }
                } header: {
                    Text("Private Key")
                } footer: {
                    Text("Paste the whole private key file, including the BEGIN and END lines. Ed25519 and RSA keys in OpenSSH format are supported.")
                }

                if needsPassphrase {
                    Section {
                        SecureField("Passphrase", text: $passphrase)
                            .focused($passphraseFocused)
                    } footer: {
                        Text("Stored in the Keychain alongside the key.")
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Import Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { importKey() }
                        .disabled(pastedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.data, .text],
                          allowsMultipleSelection: false) { result in
                loadFile(result)
            }
        }
    }

    private func importKey() {
        do {
            _ = try PrivateKeyImport.store(pastedKey,
                                           label: label,
                                           passphrase: needsPassphrase ? passphrase : nil,
                                           into: secretStore,
                                           context: ctx)
            dismiss()
        } catch PrivateKeyImportError.needsPassphrase {
            // Not a failure — the key is fine, it just has not been unlocked.
            errorMessage = nil
            needsPassphrase = true
            passphraseFocused = true
        } catch let error as PrivateKeyImportError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = PrivateKeyImportError.malformed.errorDescription
        }
    }

    private func loadFile(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        // Files chosen through the picker live outside the sandbox.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            errorMessage = String(localized: "That file could not be read as text.")
            return
        }
        pastedKey = text
        if label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            label = url.deletingPathExtension().lastPathComponent
        }
        errorMessage = nil
        needsPassphrase = PrivateKeyImport.isEncrypted(text)
    }
}
