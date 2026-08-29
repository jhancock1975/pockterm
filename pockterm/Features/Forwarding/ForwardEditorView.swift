import SwiftUI
import SwiftData

struct ForwardEditorView: View {
    @Bindable var forward: PortForward
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Host.label) private var hosts: [Host]

    var body: some View {
        NavigationStack {
            Form {
                Section("Forward") {
                    TextField("Label", text: $forward.label)
                    Picker("Type", selection: typeBinding) {
                        Text("Local").tag(ForwardType.local)
                        Text("Remote").tag(ForwardType.remote)
                        Text("Dynamic (SOCKS)").tag(ForwardType.dynamic)
                    }
                    Picker("Host", selection: $forward.host) {
                        Text("None").tag(Host?.none)
                        ForEach(hosts) { host in Text(host.label).tag(Host?.some(host)) }
                    }
                }

                Section(bindLabel) {
                    TextField("Bind Port", value: $forward.bindPort, format: .technicalPort)
                        .keyboardType(.numberPad)
                }

                if forward.type != .dynamic {
                    Section(forward.type == .local ? "Forward To (remote)" : "Forward To (local)") {
                        TextField("Host", text: $forward.remoteHost)
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Port", value: $forward.remotePort, format: .technicalPort)
                            .keyboardType(.numberPad)
                    }
                } else {
                    Section {
                        Text("A SOCKS5 proxy listens on the bind port; each connection is tunneled to its requested destination.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(forward.label.isEmpty ? String(localized: "New Forward") : forward.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var typeBinding: Binding<ForwardType> {
        Binding(get: { forward.type }, set: { forward.type = $0 })
    }

    /// Localized explicitly. This is a `String`, so it reaches `Section(_:)`
    /// through the StringProtocol overload rather than LocalizedStringKey — a
    /// plain literal here would stay English in every language.
    private var bindLabel: String {
        forward.type == .remote
            ? String(localized: "Bind Port (on server)")
            : String(localized: "Bind Port (on device)")
    }

    private var isValid: Bool {
        guard !forward.label.isEmpty, forward.host != nil, forward.bindPort > 0 else { return false }
        if forward.type == .dynamic { return true }
        return !forward.remoteHost.isEmpty && forward.remotePort > 0
    }

    private func save() {
        if forward.modelContext == nil { ctx.insert(forward) }
        try? ctx.save()
        dismiss()
    }
}
