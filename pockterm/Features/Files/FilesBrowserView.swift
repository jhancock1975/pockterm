import PhotosUI
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

/// Menu titles for the sort fields. They live here rather than on `FileSort`
/// itself so the SFTP layer stays clear of SwiftUI.
extension FileSort {
    var label: LocalizedStringKey {
        switch self {
        case .name: return "Name"
        case .date: return "Date"
        }
    }
}

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
    @State private var showingHelp = false
    @State private var showingPhotoPicker = false
    @State private var pickedMedia: [PhotosPickerItem] = []
    /// Copying picked photos out of the library before they can upload.
    @State private var preparingMedia = false
    /// A picked batch waiting on the Replace / Keep Both question.
    @State private var pendingUpload: [UploadSource] = []
    @State private var pendingConflicts: [String] = []

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
                          allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    beginUpload(urls.map { UploadSource(url: $0, isTemporary: false) })
                }
            }
            .photosPicker(isPresented: $showingPhotoPicker, selection: $pickedMedia,
                          maxSelectionCount: nil, selectionBehavior: .ordered,
                          matching: .any(of: [.images, .videos]),
                          preferredItemEncoding: .current)
            .onChange(of: pickedMedia) { _, items in
                guard !items.isEmpty else { return }
                pickedMedia = []
                Task { await importMedia(items) }
            }
            .overlay(alignment: .bottom) { uploadConfirmation }
            .sheet(item: $shareItem) { item in ActivityView(url: item.url) }
            .sheet(isPresented: $showingHelp) {
                NavigationStack {
                    HelpTopicView(topic: HelpContent.sftp)
                        .navigationTitle(HelpContent.sftp.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { showingHelp = false }
                            }
                        }
                }
            }
            .modifier(FilesBrowserAlerts(
                model: model,
                showingNewFolder: $showingNewFolder, newFolderName: $newFolderName,
                renameTarget: $renameTarget, renameText: $renameText,
                chmodTarget: $chmodTarget, chmodText: $chmodText))
            .alert(conflictTitle, isPresented: conflictPresented) {
                Button("Replace", role: .destructive) { finishUpload(.replace) }
                Button("Keep Both") { finishUpload(.keepBoth) }
                Button("Cancel", role: .cancel) {
                    model.discard(pendingUpload)
                    pendingUpload = []; pendingConflicts = []
                }
            } message: {
                Text("Replace overwrites what is already on the server.")
            }
            .alert("Upload Failed", isPresented: failuresPresented) {
                Button("OK", role: .cancel) { model.uploadFailures = [] }
            } message: {
                Text(failureMessage)
            }
        }
    }

    // MARK: Uploading

    /// Uploads straight away, or first asks about any names already taken in
    /// this folder. SFTP would otherwise overwrite them without a word.
    private func beginUpload(_ sources: [UploadSource]) {
        guard !sources.isEmpty else { return }
        let clashes = model.conflicts(for: sources.map(\.name))
        if clashes.isEmpty {
            Task { await model.upload(sources, choice: .keepBoth) }
        } else {
            pendingUpload = sources
            pendingConflicts = clashes
        }
    }

    private func finishUpload(_ choice: UploadConflictChoice) {
        let sources = pendingUpload
        pendingUpload = []; pendingConflicts = []
        Task { await model.upload(sources, choice: choice) }
    }

    /// Copies picked photos and videos out of the library, then uploads them
    /// like any other files. An item the library can't hand over is reported
    /// rather than dropped.
    private func importMedia(_ items: [PhotosPickerItem]) async {
        preparingMedia = true
        var sources: [UploadSource] = []
        var unreadable = false
        for item in items {
            if let media = try? await item.loadTransferable(type: PickedMedia.self) {
                sources.append(UploadSource(url: media.url, isTemporary: true))
            } else {
                unreadable = true
            }
        }
        preparingMedia = false
        if unreadable {
            model.actionError = String(localized: "Some items couldn't be read from your photo library.")
        }
        beginUpload(sources)
    }

    private var conflictTitle: String {
        if pendingConflicts.count == 1, let name = pendingConflicts.first {
            return String(localized: "“\(name)” already exists here")
        }
        return String(localized: "\(pendingConflicts.count) files already exist here")
    }

    private var conflictPresented: Binding<Bool> {
        Binding(get: { !pendingConflicts.isEmpty },
                set: { if !$0, !pendingConflicts.isEmpty {
                    model.discard(pendingUpload)
                    pendingUpload = []; pendingConflicts = []
                } })
    }

    private var failuresPresented: Binding<Bool> {
        Binding(get: { !model.uploadFailures.isEmpty && pendingConflicts.isEmpty },
                set: { if !$0 { model.uploadFailures = [] } })
    }

    private var failureMessage: String {
        model.uploadFailures
            .map { String(localized: "Couldn't upload “\($0.name)”: \($0.message)") }
            .joined(separator: "\n")
    }

    /// A brief "Uploaded …" pill over the bottom of the listing.
    @ViewBuilder
    private var uploadConfirmation: some View {
        if let summary = model.uploadSummary {
            Label(summaryText(summary), systemImage: "checkmark.circle.fill")
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(.regularMaterial, in: Capsule())
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .task(id: summary) {
                    try? await Task.sleep(for: .seconds(2.5))
                    withAnimation { model.uploadSummary = nil }
                }
        }
    }

    private func summaryText(_ summary: UploadSummary) -> String {
        if summary.names.count == 1, let name = summary.names.first {
            return String(localized: "Uploaded “\(name)”")
        }
        return String(localized: "Uploaded \(summary.names.count) files")
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
            ScrollViewReader { proxy in
                List {
                    if model.canGoUp {
                        Button { Task { await model.goUp() } } label: {
                            Label("..", systemImage: "arrow.up.left").foregroundStyle(.primary)
                        }
                    }
                    ForEach(model.files) { file in
                        row(file)
                            .id(file.id)
                            .listRowBackground(model.highlighted == file.id
                                               ? Color.accentColor.opacity(0.2) : nil)
                    }
                }
                .listStyle(.plain)
                .refreshable { await model.refresh() }
                .onChange(of: model.highlighted, initial: true) { _, target in
                    guard let target else { return }
                    // A beat for the fresh listing to lay out before scrolling.
                    Task {
                        try? await Task.sleep(for: .milliseconds(150))
                        withAnimation { proxy.scrollTo(target, anchor: .center) }
                        try? await Task.sleep(for: .seconds(2.5))
                        if model.highlighted == target {
                            withAnimation { model.highlighted = nil }
                        }
                    }
                }
            }
        }
    }

    /// Everything happens on a tap. A file's row opens its actions. A folder's
    /// row opens the folder, and the ⋯ beside it holds the same actions.
    @ViewBuilder
    private func row(_ file: RemoteFile) -> some View {
        if file.kind == .directory {
            HStack(spacing: 4) {
                Button { Task { await model.open(file) } } label: {
                    RemoteFileRow(file: file).foregroundStyle(.primary).contentShape(.rect)
                }
                .buttonStyle(.plain)
                Menu { rowMenu(file) } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Actions")
            }
        } else {
            Menu { rowMenu(file) } label: {
                HStack(spacing: 4) {
                    RemoteFileRow(file: file)
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }
                .foregroundStyle(.primary)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
    }

    private var pathBar: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "folder")
                Text(model.path).lineLimit(1).truncationMode(.head)
                Spacer()
                if let batch = model.batch {
                    Text("\(batch.position) of \(batch.count)").monospacedDigit()
                }
                if model.transfers.hasActive || preparingMedia {
                    ProgressView().controlSize(.small)
                }
            }
            if let transfer = model.transfers.active {
                transferProgress(transfer)
            }
        }
        .font(.system(.footnote, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// Determinate bar when the server told us the size, indeterminate when it
    /// didn't — a 0% bar that never moves reads as a hang.
    @ViewBuilder
    private func transferProgress(_ transfer: Transfer) -> some View {
        HStack(spacing: 8) {
            Image(systemName: transfer.direction == .upload
                  ? "arrow.up.circle" : "arrow.down.circle")
            Text(transfer.name).lineLimit(1).truncationMode(.middle)
            Spacer()
            if let fraction = transfer.fractionCompleted {
                Text(Self.byteCount(transfer.bytesTransferred)
                     + " / " + Self.byteCount(transfer.totalBytes))
                ProgressView(value: fraction).frame(width: 64)
            } else {
                Text(Self.byteCount(transfer.bytesTransferred))
                ProgressView().controlSize(.mini)
            }
        }
        .font(.caption2)
    }

    private static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
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

    /// The active field carries the arrow, and choosing it again flips it.
    /// A checkmark alone could not say whether Date meant newest or oldest
    /// first, which is most of what anyone wants from a date sort.
    private var sortMenu: some View {
        Menu {
            Section("Sort By") {
                ForEach(FileSort.allCases) { field in
                    Button { model.select(field) } label: {
                        if field == model.sort.field {
                            Label(field.label, systemImage: model.sort.ascending
                                  ? "chevron.up" : "chevron.down")
                        } else {
                            Text(field.label)
                        }
                    }
                }
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("Sort")
        .disabled(model.status != .loaded)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingNewFolder = true } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            .disabled(model.status != .loaded)
        }
        // Labelled, and down where a thumb reaches. It used to be one of two
        // items behind a bare + that gave no hint it could upload anything.
        ToolbarItem(placement: .bottomBar) {
            Menu {
                Button { showingUploader = true } label: {
                    Label("Files…", systemImage: "folder")
                }
                Button { showingPhotoPicker = true } label: {
                    Label("Photos & Videos…", systemImage: "photo.on.rectangle")
                }
            } label: {
                Label("Upload", systemImage: "square.and.arrow.up")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(model.status != .loaded || model.batch != nil || preparingMedia)
        }
        ToolbarItem(placement: .topBarTrailing) {
            sortMenu
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { showingHelp = true } label: {
                Image(systemName: "questionmark.circle")
            }
            .accessibilityLabel("SFTP Help")
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
