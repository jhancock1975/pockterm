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
    /// Last-modified time, when the server reported one.
    ///
    /// Not a creation date: Citadel speaks SFTP v3, whose ATTRS carry only
    /// access and modification times. A creation timestamp needs SFTP v4+,
    /// which the library does not implement — so there is nothing to show.
    let modified: Date?

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

    /// Formats an entry's timestamp for the browser subtitle: the time of day
    /// for something touched today, day and month inside the current year, and
    /// the year beyond that. Same progression as `ls -l` and Finder, so a long
    /// listing stays scannable instead of repeating today's date on every row.
    ///
    /// Locale-formatted on purpose, unlike ports and status codes — see
    /// `technicalDigits`. A date is read, not typed back into a server config,
    /// so an Arabic reader should get Arabic-Indic digits here exactly as they
    /// already do for the file size beside it.
    static func modifiedString(_ date: Date,
                               now: Date = .now,
                               calendar: Calendar = .autoupdatingCurrent,
                               locale: Locale = .autoupdatingCurrent) -> String {
        var style: Date.FormatStyle
        if calendar.isDate(date, inSameDayAs: now) {
            style = .dateTime.hour().minute()
        } else if calendar.component(.year, from: date) == calendar.component(.year, from: now) {
            style = .dateTime.day().month(.abbreviated)
        } else {
            style = .dateTime.day().month(.abbreviated).year()
        }
        // Render through the same calendar the bucketing above used. Left
        // alone, the style falls back to the current time zone, so an injected
        // calendar would sort a date by one zone and print it in another.
        style.locale = locale
        style.calendar = calendar
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    /// Joins a directory and entry name into a clean absolute path.
    static func joinPath(_ directory: String, _ name: String) -> String {
        if directory == "/" { return "/" + name }
        if directory.hasSuffix("/") { return directory + name }
        return directory + "/" + name
    }
}
