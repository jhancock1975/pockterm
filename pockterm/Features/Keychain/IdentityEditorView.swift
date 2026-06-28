import SwiftUI
import SwiftData

struct IdentityEditorView: View {
    let secretStore: SecretStore
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
            Section("Identity") {
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
                    SecureField("Password", text: $password)
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
        .navigationTitle("New Identity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }.disabled(!isValid)
            }
        }
    }

    private var isValid: Bool {
        guard !label.isEmpty, !username.isEmpty else { return false }
        return method == .password ? !password.isEmpty : selectedKey != nil
    }

    private func save() {
        let identity = Identity(label: label, username: username,
                                method: method, keyRef: selectedKey?.id)
        if method == .password {
            try? secretStore.setString(password, for: identity.id.uuidString)
        }
        ctx.insert(identity)
        try? ctx.save()
        dismiss()
    }
}

private extension Identity {
    convenience init(label: String, username: String, method: AuthMethod, keyRef: UUID?) {
        self.init(label: label, username: username, authMethod: method, keyRef: keyRef)
    }
}
