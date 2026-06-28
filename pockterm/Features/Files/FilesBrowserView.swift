import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct FilesBrowserView: View {
    @State private var model: FilesBrowserModel
    @Environment(\.dismiss) private var dismiss

    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var showingUploader = false
    @State private var renameTarget: RemoteFile?
    @State private var renameText = ""
    @State private var chmodTarget: RemoteFile?
    @State private var chmodText = ""
    @State private var shareItem: ShareItem?

    init(host: Host, secretStore: SecretStore, modelContext: ModelContext) {
        _model = State(initialValue: FilesBrowserModel(host: host, secretStore: secretStore,
                                                       modelContext: modelContext))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pathBar
                content
            }
            .navigationTitle(model.host.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .task { await model.start() }
            .onDisappear { Task { await model.disconnect() } }
            .fileImporter(isPresented: $showingUploader,
                          allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    Task { await model.upload(from: url) }
                }
            }
            .sheet(item: $shareItem) { item in ActivityView(url: item.url) }
            .modifier(FilesBrowserAlerts(
                model: model,
                showingNewFolder: $showingNewFolder, newFolderName: $newFolderName,
                renameTarget: $renameTarget, renameText: $renameText,
                chmodTarget: $chmodTarget, chmodText: $chmodText))
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.status {
        case .connecting:
            Spacer()
            ProgressView("Connecting…")
            Spacer()
        case .error(let message):
            ContentUnavailableView("SFTP Error", systemImage: "xmark.octagon", description: Text(message))
        case .loaded:
            List {
                if model.canGoUp {
                    Button { Task { await model.goUp() } } label: {
                        Label("..", systemImage: "arrow.up.left").foregroundStyle(.primary)
                    }
                }
                ForEach(model.files) { file in
                    Button { Task { await model.open(file) } } label: {
                        RemoteFileRow(file: file).foregroundStyle(.primary)
                    }
                    .contextMenu { rowMenu(file) }
                }
            }
            .listStyle(.plain)
            .refreshable { await model.refresh() }
        }
    }

    private var pathBar: some View {
        HStack {
            Image(systemName: "folder")
            Text(model.path).lineLimit(1).truncationMode(.head)
            Spacer()
            if model.transfers.hasActive { ProgressView().controlSize(.small) }
        }
        .font(.system(.footnote, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    @ViewBuilder
    private func rowMenu(_ file: RemoteFile) -> some View {
        if file.kind != .directory {
            Button { Task { if let url = await model.download(file) { shareItem = ShareItem(url: url) } } } label: {
                Label("Download", systemImage: "square.and.arrow.down")
            }
        }
        Button {
            renameTarget = file; renameText = file.name
        } label: { Label("Rename", systemImage: "pencil") }
        Button {
            chmodTarget = file
            chmodText = String(file.permissions & 0o777, radix: 8)
        } label: { Label("Permissions", systemImage: "lock") }
        Button(role: .destructive) {
            Task { await model.delete(file) }
        } label: { Label("Delete", systemImage: "trash") }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Button { showingNewFolder = true } label: { Label("New Folder", systemImage: "folder.badge.plus") }
                Button { showingUploader = true } label: { Label("Upload File", systemImage: "square.and.arrow.up") }
            } label: { Image(systemName: "plus") }
            .disabled(model.status != .loaded)
        }
        ToolbarItem(placement: .topBarLeading) {
            Button("Done") { dismiss() }
        }
    }
}

/// Identifiable wrapper so a downloaded file URL can drive a share sheet.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

/// UIActivityViewController bridge for sharing/saving a downloaded file.
struct ActivityView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// The text-entry and error alerts for the browser, factored out to keep the
/// main view readable.
private struct FilesBrowserAlerts: ViewModifier {
    @Bindable var model: FilesBrowserModel
    @Binding var showingNewFolder: Bool
    @Binding var newFolderName: String
    @Binding var renameTarget: RemoteFile?
    @Binding var renameText: String
    @Binding var chmodTarget: RemoteFile?
    @Binding var chmodText: String

    func body(content: Content) -> some View {
        content
            .alert("New Folder", isPresented: $showingNewFolder) {
                TextField("Name", text: $newFolderName)
                Button("Create") {
                    let name = newFolderName; newFolderName = ""
                    if !name.isEmpty { Task { await model.makeDirectory(named: name) } }
                }
                Button("Cancel", role: .cancel) { newFolderName = "" }
            }
            .alert("Rename", isPresented: renamePresented) {
                TextField("Name", text: $renameText)
                Button("Rename") {
                    if let file = renameTarget, !renameText.isEmpty {
                        let newName = renameText
                        Task { await model.rename(file, to: newName) }
                    }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
            .alert("Permissions (octal)", isPresented: chmodPresented) {
                TextField("e.g. 644", text: $chmodText).keyboardType(.numberPad)
                Button("Apply") {
                    if let file = chmodTarget, let mode = UInt32(chmodText, radix: 8) {
                        Task { await model.chmod(file, mode: mode) }
                    }
                    chmodTarget = nil
                }
                Button("Cancel", role: .cancel) { chmodTarget = nil }
            }
            .alert("Verify Host Key", isPresented: hostKeyPresented,
                   presenting: model.pendingHostKey) { pending in
                Button(pending.storedFingerprint == nil ? "Accept" : "Accept Changed Key",
                       role: pending.storedFingerprint == nil ? nil : .destructive) {
                    pending.resume(true); model.pendingHostKey = nil
                }
                Button("Reject", role: .cancel) { pending.resume(false); model.pendingHostKey = nil }
            } message: { pending in
                Text(pending.info.fingerprint ?? "Fingerprint unavailable")
            }
            .alert("Operation Failed", isPresented: errorPresented) {
                Button("OK", role: .cancel) { model.actionError = nil }
            } message: {
                Text(model.actionError ?? "")
            }
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }
    private var chmodPresented: Binding<Bool> {
        Binding(get: { chmodTarget != nil }, set: { if !$0 { chmodTarget = nil } })
    }
    private var hostKeyPresented: Binding<Bool> {
        Binding(get: { model.pendingHostKey != nil },
                set: { if !$0, let pending = model.pendingHostKey { pending.resume(false); model.pendingHostKey = nil } })
    }
    private var errorPresented: Binding<Bool> {
        Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })
    }
}
