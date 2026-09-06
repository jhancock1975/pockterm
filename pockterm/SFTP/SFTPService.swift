import Foundation
import Citadel
import Crypto
import NIOCore

/// Owns an SSH connection dedicated to SFTP and exposes file operations. Host
/// key validation reuses the same prompt flow as the terminal.
actor SFTPService {
    private var client: SSHClient?
    private var sftp: SFTPClient?

    func connect(_ creds: SSHCredentials,
                 onHostKey: @escaping @Sendable (PresentedHostKey) async -> Bool) async throws {
        let method = try creds.authenticationMethod()
        let validator = CallbackHostKeyValidator(address: creds.host, port: creds.port, decide: onHostKey)
        let connection = try await SSHClient.connect(
            host: creds.host,
            port: creds.port,
            authenticationMethod: method,
            hostKeyValidator: .custom(validator),
            reconnect: .never,
            algorithms: .pockterm)
        client = connection
        sftp = try await connection.openSFTP()
    }

    func homeDirectory() async throws -> String {
        try await requireSFTP().getRealPath(atPath: ".")
    }

    func realPath(_ path: String) async throws -> String {
        try await requireSFTP().getRealPath(atPath: path)
    }

    /// Lists a directory, omitting `.`/`..`, directories first then by name.
    func list(_ path: String) async throws -> [RemoteFile] {
        let sftp = try requireSFTP()
        let resolved = try await sftp.getRealPath(atPath: path)
        let names = try await sftp.listDirectory(atPath: resolved)

        var files: [RemoteFile] = []
        for name in names {
            for component in name.components where component.filename != "." && component.filename != ".." {
                let mode = component.attributes.permissions ?? 0
                files.append(RemoteFile(
                    id: RemoteFile.joinPath(resolved, component.filename),
                    name: component.filename,
                    kind: RemoteFile.kind(fromMode: mode),
                    size: component.attributes.size ?? 0,
                    permissions: mode))
            }
        }
        return files.sorted {
            let lhs = ($0.kind == .directory ? 0 : 1, $0.name.lowercased())
            let rhs = ($1.kind == .directory ? 0 : 1, $1.name.lowercased())
            return lhs < rhs
        }
    }

    /// Bytes moved per round trip. Servers are free to return short reads, which
    /// the loops below handle by advancing on the count actually received.
    private static let chunkSize = 32_768

    /// How much `downloadData` will pull into memory before giving up.
    static let inMemoryDownloadLimit = 1 << 20  // 1 MiB

    /// Streams a remote file to `destination`, one chunk at a time — the whole
    /// file is never resident. `progress` reports (transferred, total); total is
    /// 0 when the server does not report a size.
    func download(_ path: String, to destination: URL,
                  progress: @Sendable (Int64, Int64) -> Void = { _, _ in }) async throws {
        let file = try await requireSFTP().openFile(filePath: path, flags: [.read])
        do {
            try await stream(file, to: destination, progress: progress)
            try await file.close()
        } catch {
            try? await file.close()
            throw error
        }
    }

    private func stream(_ file: SFTPFile, to destination: URL,
                        progress: @Sendable (Int64, Int64) -> Void) async throws {
        let total = Int64(clamping: (try? await file.readAttributes())?.size ?? 0)

        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var offset: UInt64 = 0
        while true {
            try Task.checkCancellation()
            var chunk = try await file.read(from: offset, length: UInt32(Self.chunkSize))
            let count = chunk.readableBytes
            guard count > 0, let bytes = chunk.readBytes(length: count) else { break }
            try handle.write(contentsOf: bytes)
            offset &+= UInt64(count)
            progress(Int64(clamping: offset), total)
        }
        try handle.synchronize()
    }

    /// Streams a local file to `path`, one chunk at a time.
    func upload(from source: URL, to path: String,
                progress: @Sendable (Int64, Int64) -> Void = { _, _ in }) async throws {
        let total = Int64((try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        let reader = try FileHandle(forReadingFrom: source)
        defer { try? reader.close() }

        let file = try await requireSFTP().openFile(filePath: path, flags: [.write, .create, .truncate])
        do {
            var offset: UInt64 = 0
            while true {
                try Task.checkCancellation()
                guard let data = try reader.read(upToCount: Self.chunkSize), !data.isEmpty else { break }
                try await file.write(ByteBuffer(bytes: data), at: offset)
                offset &+= UInt64(data.count)
                progress(Int64(clamping: offset), total)
            }
            try await file.close()
        } catch {
            try? await file.close()
            throw error
        }
    }

    /// Reads a remote file into memory for callers that need the bytes rather
    /// than a file on disk (the AI assistant reading file contents). Capped at
    /// `maxBytes` so a large file cannot exhaust memory — real transfers go
    /// through `download(_:to:)`.
    func downloadData(_ path: String, maxBytes: Int = SFTPService.inMemoryDownloadLimit) async throws -> Data {
        let file = try await requireSFTP().openFile(filePath: path, flags: [.read])
        do {
            var out = Data()
            var offset: UInt64 = 0
            while out.count < maxBytes {
                var chunk = try await file.read(from: offset, length: UInt32(Self.chunkSize))
                let count = chunk.readableBytes
                guard count > 0, let bytes = chunk.readBytes(length: count) else { break }
                out.append(contentsOf: bytes)
                offset &+= UInt64(count)
            }
            try await file.close()
            return out.count > maxBytes ? out.prefix(maxBytes) : out
        } catch {
            try? await file.close()
            throw error
        }
    }

    /// Writes a small in-memory payload (agent-authored files). Anything sized
    /// by the user goes through `upload(from:to:)`.
    func upload(_ data: Data, to path: String) async throws {
        let file = try await requireSFTP().openFile(filePath: path, flags: [.write, .create, .truncate])
        do {
            try await file.write(ByteBuffer(bytes: data), at: 0)
            try await file.close()
        } catch {
            try? await file.close()
            throw error
        }
    }

    func makeDirectory(_ path: String) async throws {
        try await requireSFTP().createDirectory(atPath: path)
    }

    func remove(_ path: String) async throws {
        try await requireSFTP().remove(at: path)
    }

    func removeDirectory(_ path: String) async throws {
        try await requireSFTP().rmdir(at: path)
    }

    func rename(_ from: String, to: String) async throws {
        try await requireSFTP().rename(at: from, to: to)
    }

    func chmod(_ path: String, mode: UInt32) async throws {
        var attributes = SFTPFileAttributes()
        attributes.permissions = mode
        try await requireSFTP().setAttributes(at: path, to: attributes)
    }

    func disconnect() async {
        try? await sftp?.close()
        try? await client?.close()
        sftp = nil
        client = nil
    }

    private func requireSFTP() throws -> SFTPClient {
        guard let sftp else { throw SSHEngineError.notConnected }
        return sftp
    }
}
