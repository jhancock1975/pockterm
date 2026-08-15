import SwiftUI
import SwiftData

/// A slim SFTP browser for attaching one remote file to the assistant chat:
/// navigate directories, tap a file to download and pick it.
struct RemoteFilePickerView: View {
    @State private var model: FilesBrowserModel
    private let onPick: (String, Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var downloading: RemoteFile?

    init(host: Host, secretStore: SecretStore, modelContext: ModelContext,
         onPick: @escaping (String, Data) -> Void) {
        _model = State(initialValue: FilesBrowserModel(host: host, secretStore: secretStore,
                                                       modelContext: modelContext))
        self.onPick = onPick
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.status {
                case .connecting:
                    ProgressView("Connecting…")
                case .error(let message):
                    ContentUnavailableView("Connection Failed", systemImage: "xmark.octagon",
                                           description: Text(message))
                case .loaded:
                    fileList
                }
            }
            .navigationTitle(model.path)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .task { await model.start() }
        .onDisappear { Task { await model.disconnect() } }
        .alert("Verify Host Key", isPresented: hostKeyPresented, presenting: model.pendingHostKey) { pending in
            Button("Accept") { pending.resume(true); model.pendingHostKey = nil }
            Button("Reject", role: .cancel) { pending.resume(false); model.pendingHostKey = nil }
        } message: { pending in
            Text("\(pending.info.address):\(pending.info.port.technicalDigits)\n\(pending.info.fingerprint ?? "")")
        }
    }

    private var fileList: some View {
        List {
            if model.canGoUp {
                Button {
                    Task { await model.goUp() }
                } label: {
                    Label("..", systemImage: "arrow.up.doc")
                }
            }
            ForEach(model.files) { file in
                Button {
                    open(file)
                } label: {
                    HStack {
                        Label(file.name, systemImage: file.kind == .directory ? "folder" : "doc.text")
                            .lineLimit(1)
                        Spacer()
                        if downloading?.id == file.id { ProgressView() }
                    }
                }
                .disabled(downloading != nil)
            }
        }
    }

    private func open(_ file: RemoteFile) {
        if file.kind == .directory {
            Task { await model.open(file) }
            return
        }
        downloading = file
        Task {
            if let url = await model.download(file), let data = try? Data(contentsOf: url) {
                onPick(file.name, data)
                dismiss()
            }
            downloading = nil
        }
    }

    private var hostKeyPresented: Binding<Bool> {
        Binding(get: { model.pendingHostKey != nil },
                set: { presented in
                    if !presented, let pending = model.pendingHostKey {
                        pending.resume(false)
                        model.pendingHostKey = nil
                    }
                })
    }
}
