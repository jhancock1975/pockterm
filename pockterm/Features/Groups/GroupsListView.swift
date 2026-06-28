import SwiftUI
import SwiftData

struct GroupsListView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \HostGroup.name) private var groups: [HostGroup]
    @State private var editing: HostGroup?

    var body: some View {
        NavigationStack {
            Group {
                if groups.isEmpty {
                    ContentUnavailableView("No Groups", systemImage: "folder",
                                           description: Text("Tap + to organize hosts into groups."))
                } else {
                    List {
                        ForEach(groups) { group in
                            Button { editing = group } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.name).font(.headline)
                                    if let parent = group.parent {
                                        Text("in \(parent.name)").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { for i in $0 { ctx.delete(groups[i]) } }
                    }
                }
            }
            .navigationTitle("Groups")
            .toolbar {
                Button { editing = HostGroup(name: "") } label: { Image(systemName: "plus") }
            }
            .sheet(item: $editing) { group in
                GroupEditorView(group: group)
            }
        }
    }
}
