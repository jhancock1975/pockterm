import SwiftUI
import SwiftData

struct SnippetEditorView: View {
    @Bindable var snippet: Snippet
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("Label", text: $snippet.label)
                Section("Command") {
                    TextEditor(text: $snippet.command)
                        .frame(minHeight: 120)
                        .font(.system(.callout, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle(snippet.label.isEmpty ? "New Snippet" : snippet.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(snippet.label.isEmpty || snippet.command.isEmpty)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func save() {
        if snippet.modelContext == nil { ctx.insert(snippet) }
        try? ctx.save()
        dismiss()
    }
}
