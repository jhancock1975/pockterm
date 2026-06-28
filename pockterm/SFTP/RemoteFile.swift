import Foundation

enum FileKind: Equatable {
    case directory
    case regular
    case symlink
    case other
}

/// A remote filesystem entry returned by SFTP, reduced to what the browser
/// needs to display and act on.
struct RemoteFile: Identifiable, Equatable {
    /// Full remote path — unique within a listing.
    let id: String
    let name: String
    let kind: FileKind
    let size: UInt64
    let permissions: UInt32

    var path: String { id }

    /// Classifies a POSIX mode by its file-type bits (S_IFMT).
    static func kind(fromMode mode: UInt32) -> FileKind {
        switch mode & 0o170000 {
        case 0o040000: return .directory
        case 0o100000: return .regular
        case 0o120000: return .symlink
        default: return .other
        }
    }

    /// Renders the low 9 permission bits as `rwxr-xr-x`.
    static func permissionString(_ mode: UInt32) -> String {
        let bits = mode & 0o777
        let flags = ["r", "w", "x"]
        var out = ""
        for shift in [6, 3, 0] {
            let triad = (bits >> UInt32(shift)) & 0o7
            for (i, flag) in flags.enumerated() {
                out += (triad & (0o4 >> UInt32(i))) != 0 ? flag : "-"
            }
        }
        return out
    }

    /// Joins a directory and entry name into a clean absolute path.
    static func joinPath(_ directory: String, _ name: String) -> String {
        if directory == "/" { return "/" + name }
        if directory.hasSuffix("/") { return directory + name }
        return directory + "/" + name
    }
}
