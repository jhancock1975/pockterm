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
            reconnect: .never)
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

    func download(_ path: String) async throws -> Data {
        let file = try await requireSFTP().openFile(filePath: path, flags: [.read])
        do {
            let buffer = try await file.readAll()
            try await file.close()
            return Data(buffer.readableBytesView)
        } catch {
            try? await file.close()
            throw error
        }
    }

    func upload(_ data: Data, to path: String) async throws {
        let file = try await requireSFTP().openFile(filePath: path, flags: [.write, .create, .truncate])
        do {
            try await file.write(ByteBuffer(bytes: Array(data)), at: 0)
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
