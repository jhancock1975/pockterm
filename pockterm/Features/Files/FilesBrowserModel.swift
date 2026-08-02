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

    init(host: Host, secretStore: SecretStore, modelContext: ModelContext) {
        self.host = host
        self.secretStore = secretStore
        self.modelContext = modelContext
    }

    var canGoUp: Bool { path != "/" }

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
            try await sftp.connect(creds) { [weak self] presented in
                await self?.decideHostKey(presented) ?? false
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
            files = listed
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

    /// Downloads a file to a temporary URL for sharing/saving.
    func download(_ file: RemoteFile) async -> URL? {
        let transfer = transfers.start(name: file.name, direction: .download)
        do {
            let data = try await sftp.download(file.path)
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(file.name)
            try data.write(to: url)
            transfers.finish(transfer, error: nil)
            return url
        } catch {
            transfers.finish(transfer, error: error)
            return nil
        }
    }

    func upload(from url: URL) async {
        let name = url.lastPathComponent
        let transfer = transfers.start(name: name, direction: .upload)
        do {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            try await sftp.upload(data, to: RemoteFile.joinPath(path, name))
            transfers.finish(transfer, error: nil)
            await refresh()
        } catch {
            transfers.finish(transfer, error: error)
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
            actionError = error.localizedDescription
        }
    }

}
