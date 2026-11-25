import SwiftUI
import SwiftData

struct IdentityEditorView: View {
    let secretStore: SecretStore
    /// The credentials being edited, or nil to make new ones.
    var identity: Identity? = nil
    /// Shown as a sheet, which has no back button to leave by.
    var showsCancel = false
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \SSHKeyRecord.label) private var keys: [SSHKeyRecord]
    @State private var label = ""
    @State private var username = ""
    @State private var method: AuthMethod = .password
    @State private var password = ""
    @State private var selectedKey: SSHKeyRecord?

    var body: some View {
        Form {
            Section("Credentials") {
                TextField("Label", text: $label)
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            Section("Authentication") {
                Picker("Method", selection: $method) {
                    Text("Password").tag(AuthMethod.password)
                    Text("Key").tag(AuthMethod.key)
                }
                .pickerStyle(.segmented)

                if method == .password {
                    SecureField(keepsPassword ? "Unchanged" : "Password", text: $password)
                } else {
                    Picker("Key", selection: $selectedKey) {
                        Text("None").tag(SSHKeyRecord?.none)
                        ForEach(keys) { key in
                            Text(key.label).tag(SSHKeyRecord?.some(key))
                        }
                    }
                }
            }
        }
        .navigationTitle(identity == nil ? "New Credentials" : "Edit Credentials")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: load)
        .toolbar {
            if showsCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!isValid)
            }
        }
    }

    /// Editing password credentials: an empty field keeps the stored password,
    /// which is never shown.
    private var keepsPassword: Bool {
        identity?.authMethod == .password
    }

    private var isValid: Bool {
        guard !label.isEmpty, !username.isEmpty else { return false }
        if method == .key { return selectedKey != nil }
        return !password.isEmpty || keepsPassword
    }

    private func load() {
        guard let identity, label.isEmpty else { return }
        label = identity.label
        username = identity.username
        method = identity.authMethod
        selectedKey = keys.first { $0.id == identity.keyRef }
    }

    private func save() {
        let target: Identity
        if let identity {
            target = identity
            target.label = label
            target.username = username
            target.authMethod = method
            target.keyRef = method == .key ? selectedKey?.id : nil
        } else {
            target = Identity(label: label, username: username,
                              method: method, keyRef: selectedKey?.id)
            ctx.insert(target)
        }
        if method == .password {
            if !password.isEmpty { try? secretStore.setString(password, for: target.id.uuidString) }
        } else {
            // Switched to a key: don't keep a password nothing uses.
            try? secretStore.delete(target.id.uuidString)
        }
        try? ctx.save()
        dismiss()
    }
}

private extension Identity {
    convenience init(label: String, username: String, method: AuthMethod, keyRef: UUID?) {
        self.init(label: label, username: username, authMethod: method, keyRef: keyRef)
    }
}
