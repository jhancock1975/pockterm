import Foundation
import SwiftData

/// Drives the SFTP files browser for a single host: connection, listing,
/// navigation, transfers, and management operations.
@MainActor
@Observable
final class FilesBrowserModel: HostKeyDeciding {
    enum Status: Equatable {
        case connecting
        case loaded
        case error(String)
    }

    let host: Host
    private let secretStore: SecretStore
    let modelContext: ModelContext
    private let sftp = SFTPService()
    let transfers = TransferQueue()

    var path = "/"
    var files: [RemoteFile] = []
    var status: Status = .connecting
    var pendingHostKey: PendingHostKey?
    var actionError: String?

    /// Where a multi-file upload has got to, for the path bar's "2 of 5".
    private(set) var batch: UploadBatch?
    /// The file the listing scrolls to and briefly highlights after an upload.
    var highlighted: String?
    /// What the last upload put on the server, for its confirmation.
    var uploadSummary: UploadSummary?
    /// Uploads that failed, each shown with the server's reason.
    var uploadFailures: [UploadFailure] = []

    /// What the visible listing is ordered by. Chosen once and remembered, so
    /// a browser opened to hunt for this morning's render is still in date
    /// order tomorrow morning.
    private(set) var sort: FileSortOrder
    private let defaults: UserDefaults
    private var started = false

    init(host: Host, secretStore: SecretStore, modelContext: ModelContext,
         defaults: UserDefaults = .standard) {
        self.host = host
        self.secretStore = secretStore
        self.modelContext = modelContext
        self.defaults = defaults
        self.sort = FileSortOrder(reading: defaults)
    }

    func select(_ field: FileSort) {
        sort.select(field)
        sort.save(to: defaults)
        files = sort.applied(to: files)
    }

    var canGoUp: Bool { path != "/" }

    /// Whether the browser should connect as it appears: the first time,
    /// and again after a failure. Glasses mode's browser reappears with every
    /// tab switch, and reconnecting then would cut a transfer in flight.
    static func needsStart(started: Bool, status: Status) -> Bool {
        if case .error = status { return true }
        return !started
    }

    func startIfNeeded() async {
        guard Self.needsStart(started: started, status: status) else { return }
        started = true
        await start()
    }

    func start() async {
        let creds: SSHCredentials
        switch HostConnection.credentials(for: host, secretStore: secretStore) {
        case .failure(let message):
            status = .error(message)
            return
        case .success(let resolved):
            creds = resolved
        }
        do {
            try await connectCheckingHostKey { [sftp] validate in
                try await sftp.connect(creds, onHostKey: validate)
            }
            let home = try await sftp.homeDirectory()
            await navigate(to: home)
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func navigate(to newPath: String) async {
        status = .connecting
        do {
            let listed = try await sftp.list(newPath)
            path = (try? await sftp.realPath(newPath)) ?? newPath
            files = sort.applied(to: listed)
            status = .loaded
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    func open(_ file: RemoteFile) async {
        if file.kind == .directory { await navigate(to: file.path) }
    }

    func goUp() async {
        guard canGoUp else { return }
        let parent = (path as NSString).deletingLastPathComponent
        await navigate(to: parent.isEmpty ? "/" : parent)
    }

    func refresh() async {
        await navigate(to: path)
    }

    func makeDirectory(named name: String) async {
        await perform { try await self.sftp.makeDirectory(RemoteFile.joinPath(self.path, name)) }
    }

    func delete(_ file: RemoteFile) async {
        await perform {
            if file.kind == .directory {
                try await self.sftp.removeDirectory(file.path)
            } else {
                try await self.sftp.remove(file.path)
            }
        }
    }

    func rename(_ file: RemoteFile, to newName: String) async {
        await perform {
            try await self.sftp.rename(file.path, to: RemoteFile.joinPath(self.path, newName))
        }
    }

    func chmod(_ file: RemoteFile, mode: UInt32) async {
        await perform { try await self.sftp.chmod(file.path, mode: mode) }
    }

    /// Downloads a file to a temporary URL for sharing/saving. The file is
    /// streamed straight to disk, so size is bounded by storage, not memory.
    func download(_ file: RemoteFile) async -> URL? {
        let transfer = transfers.start(name: file.name, direction: .download)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
        do {
            try? FileManager.default.removeItem(at: url)
            try await sftp.download(file.path, to: url,
                                    progress: progressHandler(for: transfer))
            transfers.finish(transfer, error: nil)
            return url
        } catch {
            // Don't leave a truncated file behind for the share sheet to offer.
            try? FileManager.default.removeItem(at: url)
            transfers.finish(transfer, error: error)
            // A failed download used to vanish with its progress row.
            actionError = String(localized: "Couldn't download “\(file.name)”: \(SFTPErrorText.describe(error))")
            return nil
        }
    }

    /// Names in the current folder that uploading `names` would clash with.
    func conflicts(for names: [String]) -> [String] {
        UploadNaming.conflicts(names, existing: Set(files.map(\.name)))
    }

    /// Uploads files one after another into the current folder. A failure
    /// doesn't stop the rest: each is reported afterwards, next to a summary
    /// of what did land, and the listing scrolls to the last file uploaded.
    func upload(_ sources: [UploadSource], choice: UploadConflictChoice) async {
        let targets = UploadNaming.remoteNames(for: sources.map(\.name),
                                               existing: Set(files.map(\.name)), choice: choice)
        var uploaded: [String] = []
        var failures: [UploadFailure] = []
        for (index, (source, target)) in zip(sources, targets).enumerated() {
            batch = UploadBatch(position: index + 1, count: sources.count)
            let transfer = transfers.start(name: target, direction: .upload)
            do {
                // Files-picker URLs are security-scoped. A temporary copy of a
                // photo isn't, and this is then a harmless no-op.
                let access = source.url.startAccessingSecurityScopedResource()
                defer { if access { source.url.stopAccessingSecurityScopedResource() } }
                try await sftp.upload(from: source.url, to: RemoteFile.joinPath(path, target),
                                      progress: progressHandler(for: transfer))
                transfers.finish(transfer, error: nil)
                uploaded.append(target)
            } catch {
                transfers.finish(transfer, error: error)
                failures.append(UploadFailure(name: source.name, message: SFTPErrorText.describe(error)))
            }
        }
        batch = nil
        discard(sources)
        await refresh()
        if let last = uploaded.last { highlighted = RemoteFile.joinPath(path, last) }
        uploadSummary = uploaded.isEmpty ? nil : UploadSummary(names: uploaded)
        uploadFailures = failures
    }

    /// Deletes the temporary copies made for photo-library uploads, whether
    /// they went up or the user cancelled.
    func discard(_ sources: [UploadSource]) {
        for source in sources where source.isTemporary {
            try? FileManager.default.removeItem(at: source.url.deletingLastPathComponent())
        }
    }

    /// Bridges byte counts from the SFTP actor back onto the main actor, where
    /// the queue the UI observes lives.
    private func progressHandler(for transfer: Transfer) -> @Sendable (Int64, Int64) -> Void {
        let queue = transfers
        return { bytes, total in
            Task { @MainActor in queue.update(transfer, bytes: bytes, total: total) }
        }
    }

    func disconnect() async {
        await sftp.disconnect()
    }

    /// Runs a mutating operation then refreshes; surfaces errors to the UI.
    private func perform(_ operation: @escaping () async throws -> Void) async {
        do {
            try await operation()
            await refresh()
        } catch {
            actionError = SFTPErrorText.describe(error)
        }
    }

}
