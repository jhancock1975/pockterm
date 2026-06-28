import SwiftUI
import SwiftData

struct HostEditorView: View {
    let secretStore: SecretStore
    @Bindable var host: Host
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Identity.label) private var identities: [Identity]

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection") {
                    TextField("Label", text: $host.label)
                    TextField("Address", text: $host.address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Port", value: $host.port, format: .number)
                        .keyboardType(.numberPad)
                }
                Section("Identity") {
                    Picker("Identity", selection: $host.identity) {
                        Text("None").tag(Identity?.none)
                        ForEach(identities) { id in
                            Text(id.label).tag(Identity?.some(id))
                        }
                    }
                    NavigationLink("New Identity") {
                        IdentityEditorView(secretStore: secretStore)
                    }
                }
            }
            .navigationTitle(host.label.isEmpty ? "New Host" : host.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(host.address.isEmpty || host.label.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        if host.modelContext == nil { ctx.insert(host) }
        try? ctx.save()
        dismiss()
    }
}
