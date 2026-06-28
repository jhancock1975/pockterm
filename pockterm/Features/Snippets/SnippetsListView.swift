import SwiftUI
import SwiftData

struct SnippetsListView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Snippet.label) private var snippets: [Snippet]
    @State private var editing: Snippet?

    var body: some View {
        NavigationStack {
            Group {
                if snippets.isEmpty {
                    ContentUnavailableView("No Snippets", systemImage: "text.badge.plus",
                                           description: Text("Tap + to save a reusable command."))
                } else {
                    List {
                        ForEach(snippets) { snippet in
                            Button { editing = snippet } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(snippet.label).font(.headline)
                                    Text(snippet.command)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .onDelete { for i in $0 { ctx.delete(snippets[i]) } }
                    }
                }
            }
            .navigationTitle("Snippets")
            .toolbar {
                Button { editing = Snippet(label: "", command: "") } label: { Image(systemName: "plus") }
            }
            .sheet(item: $editing) { snippet in
                SnippetEditorView(snippet: snippet)
            }
        }
    }
}
