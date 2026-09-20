import Foundation

nonisolated enum FileKind: Equatable {
    case directory
    case regular
    case symlink
    case other
}

/// A remote filesystem entry returned by SFTP, reduced to what the browser
/// needs to display and act on.
nonisolated struct RemoteFile: Identifiable, Equatable {
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

    /// Formats an entry's timestamp for the browser subtitle: day, month and
    /// clock time, with the year added once the file is older than the current
    /// one.
    ///
    /// `ls -l` drops the time on anything but today's files and drops the date
    /// on today's; this keeps both on every row. A subtitle reading `09:50`
    /// only means "today" if you already know what the other rows look like,
    /// and a listing where some rows carry a time and some do not cannot be
    /// scanned by age at all. The year is the one part still worth eliding —
    /// it is implied for most of what anyone browses, and the line is tight.
    ///
    /// Date and time are formatted apart and joined with a space instead of
    /// being asked for as one style, because a combined style splices in the
    /// locale's connector word — `Sep 18 at 10:44 AM`, `18 sept. à 10:44` —
    /// and that is three characters spent on nothing in a row that truncates.
    ///
    /// Locale-formatted on purpose, unlike ports and status codes — see
    /// `technicalDigits`. A date is read, not typed back into a server config,
    /// so an Arabic reader should get Arabic-Indic digits here exactly as they
    /// already do for the file size beside it.
    static func modifiedString(_ date: Date,
                               now: Date = .now,
                               calendar: Calendar = .autoupdatingCurrent,
                               locale: Locale = .autoupdatingCurrent) -> String {
        // Render through the same calendar the bucketing below uses. Left
        // alone, a style falls back to the current time zone, so an injected
        // calendar would sort a date by one zone and print it in another.
        func rendered(_ style: Date.FormatStyle) -> String {
            var style = style
            style.locale = locale
            style.calendar = calendar
            style.timeZone = calendar.timeZone
            return date.formatted(style)
        }

        let thisYear = calendar.component(.year, from: date)
            == calendar.component(.year, from: now)
        let day: Date.FormatStyle = thisYear
            ? .dateTime.day().month(.abbreviated)
            : .dateTime.day().month(.abbreviated).year()
        return rendered(day) + " " + rendered(.dateTime.hour().minute())
    }

    /// Orders a listing for display.
    ///
    /// By name, directories come first in both directions — that is what makes
    /// a browser navigable, and reversing the order is meant to flip the
    /// alphabet, not to bury the folders. By date they do not: the whole point
    /// of date order is "what changed last", and a directory clump at the top
    /// would hide the file you came for.
    ///
    /// Entries the server reported no timestamp for sort last whichever way
    /// the arrow points, rather than winning the top of a newest-first list by
    /// accident. Ties break on name, because `sorted(by:)` is not stable and a
    /// directory of build output shares mtimes constantly — without this the
    /// rows would reshuffle on every refresh.
    static func sorted(_ files: [RemoteFile], by field: FileSort,
                       ascending: Bool) -> [RemoteFile] {
        files.sorted { a, b in
            switch field {
            case .name:
                if (a.kind == .directory) != (b.kind == .directory) {
                    return a.kind == .directory
                }
            case .date:
                switch (a.modified, b.modified) {
                case (nil, nil): break
                case (nil, _): return false
                case (_, nil): return true
                case (let lhs?, let rhs?) where lhs != rhs:
                    return ascending ? lhs < rhs : lhs > rhs
                default: break
                }
            }
            let order = a.name.localizedStandardCompare(b.name)
            if order != .orderedSame {
                let byName = order == .orderedAscending
                // Only the name field reverses here; a date tie stays A–Z so
                // the secondary order does not flip about under the user.
                return field == .name && !ascending ? !byName : byName
            }
            // Two names a locale considers identical — different Unicode
            // normalizations of the same letters, say. Falling through to
            // `!byName` would claim a < b AND b < a, and `sorted(by:)` traps on
            // a comparator that does that. The path is unique in a listing.
            return a.id < b.id
        }
    }

    /// Joins a directory and entry name into a clean absolute path.
    static func joinPath(_ directory: String, _ name: String) -> String {
        if directory == "/" { return "/" + name }
        if directory.hasSuffix("/") { return directory + name }
        return directory + "/" + name
    }
}
