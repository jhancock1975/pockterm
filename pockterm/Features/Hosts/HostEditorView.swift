import SwiftUI
import SwiftData

struct HostEditorView: View {
    let secretStore: SecretStore
    @Bindable var host: Host
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Identity.label) private var identities: [Identity]
    @Query(sort: \HostGroup.name) private var groups: [HostGroup]

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
                    Picker("Keep-alive", selection: $host.keepAliveSeconds) {
                        Text("Default (inherit)").tag(0)
                        ForEach(KeepAlive.options.filter { $0.seconds != 0 }) { opt in
                            Text(opt.label).tag(opt.seconds)
                        }
                    }
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
                Section("Organization") {
                    Picker("Group", selection: $host.group) {
                        Text("None").tag(HostGroup?.none)
                        ForEach(groups) { group in
                            Text(group.name).tag(HostGroup?.some(group))
                        }
                    }
                    Toggle("Favorite", isOn: $host.isFavorite)
                }
                Section("Appearance") {
                    Picker("Theme", selection: $host.themeID) {
                        Text("Default (inherit)").tag(String?.none)
                        ForEach(TerminalTheme.all) { theme in
                            Text(theme.name).tag(String?.some(theme.id))
                        }
                    }
                    Picker("Font", selection: $host.fontID) {
                        Text("Default (inherit)").tag(String?.none)
                        ForEach(TerminalFont.available()) { font in
                            Text(font.name).tag(String?.some(font.id))
                        }
                    }
                    Stepper(host.fontSize == 0 ? "Size: Default"
                                               : "Size: \(host.fontSize)pt",
                            value: $host.fontSize,
                            in: 0...TerminalZoom.maxSize)
                    ThemePreviewRow(themeID: host.themeID ?? "default",
                                    fontID: host.fontID ?? "system")
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
        if host.fontSize != 0 && host.fontSize < TerminalZoom.minSize {
            host.fontSize = TerminalZoom.minSize
        }
        try? ctx.save()
        dismiss()
    }
}
