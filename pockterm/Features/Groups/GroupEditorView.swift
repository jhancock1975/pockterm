import SwiftUI
import SwiftData

struct GroupEditorView: View {
    @Bindable var group: HostGroup
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \HostGroup.name) private var allGroups: [HostGroup]
    @Query(sort: \Identity.label) private var identities: [Identity]
    @State private var inheritPort = true
    @State private var portValue = 22

    var body: some View {
        NavigationStack {
            Form {
                Section("Group") {
                    TextField("Name", text: $group.name)
                    Picker("Parent", selection: $group.parent) {
                        Text("None").tag(HostGroup?.none)
                        ForEach(allGroups.filter { $0.id != group.id }) { g in
                            Text(g.name).tag(HostGroup?.some(g))
                        }
                    }
                }
                Section("Defaults inherited by hosts") {
                    Picker("Default Identity", selection: $group.defaultIdentity) {
                        Text("None").tag(Identity?.none)
                        ForEach(identities) { id in
                            Text(id.label).tag(Identity?.some(id))
                        }
                    }
                    Toggle("Set default port", isOn: $inheritPort.inverted)
                    if !inheritPort {
                        TextField("Port", value: $portValue, format: .number)
                            .keyboardType(.numberPad)
                    }
                }
            }
            .navigationTitle(group.name.isEmpty ? "New Group" : group.name)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let p = group.defaultPort { inheritPort = false; portValue = p }
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(group.name.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        group.defaultPort = inheritPort ? nil : portValue
        if group.modelContext == nil { ctx.insert(group) }
        try? ctx.save()
        dismiss()
    }
}

private extension Binding where Value == Bool {
    var inverted: Binding<Bool> {
        Binding(get: { !wrappedValue }, set: { wrappedValue = !$0 })
    }
}
