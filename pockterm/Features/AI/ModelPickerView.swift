import SwiftUI

/// Picks the model for the active provider. Shows the cached list instantly;
/// a fresh list fetched in under a second replaces it, anything slower waits
/// in the "updated" banner so the visible list never shifts mid-scroll.
struct ModelPickerView: View {
    let settings: AISettings
    @State private var catalog: ModelCatalog
    @State private var search = ""
    @State private var customModel = ""
    @Environment(\.dismiss) private var dismiss

    init(settings: AISettings, apiKey: String?) {
        self.settings = settings
        _catalog = State(initialValue: ModelCatalog(provider: settings.activeProvider,
                                                    apiKey: apiKey))
    }

    private var filteredModels: [String] {
        search.isEmpty ? catalog.visibleModels
                       : catalog.visibleModels.filter { $0.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            if catalog.pendingUpdate != nil {
                Button {
                    catalog.applyPendingUpdate()
                } label: {
                    Label("Model list updated — tap to show", systemImage: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.tint)
                }
            }

            Section {
                if catalog.visibleModels.isEmpty && catalog.isRefreshing {
                    HStack {
                        ProgressView()
                        Text("Loading models…").foregroundStyle(.secondary)
                    }
                }
                ForEach(filteredModels, id: \.self) { model in
                    Button {
                        settings.model = model
                        dismiss()
                    } label: {
                        HStack {
                            Text(model).foregroundStyle(.primary)
                            Spacer()
                            if model == settings.model {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } footer: {
                if catalog.isRefreshing && !catalog.visibleModels.isEmpty {
                    Label("Checking \(catalog.provider.displayName) for new models…",
                          systemImage: "arrow.triangle.2.circlepath")
                } else if catalog.refreshFailed {
                    Text("Couldn't reach \(catalog.provider.displayName); showing the cached list.")
                }
            }

            Section("Custom") {
                HStack {
                    TextField("Model id", text: $customModel)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button("Use") {
                        settings.model = customModel.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .disabled(customModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
        .task { catalog.startRefresh() }
        .onDisappear { catalog.cancel() }
    }
}
