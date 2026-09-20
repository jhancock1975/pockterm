import Foundation

/// What a listing is ordered by. Persisted as a raw string, so the cases are
/// named rather than numbered.
nonisolated enum FileSort: String, CaseIterable, Identifiable, Equatable {
    case name
    case date

    var id: String { rawValue }

    /// The direction each field is useful in before anyone touches it. A–Z for
    /// names, newest-first for dates: nobody opens a directory hoping to find
    /// the oldest thing in it.
    var defaultAscending: Bool { self == .name }
}

/// The browser's sort choice, and the whole of the logic for changing and
/// remembering it.
///
/// Split out of `FilesBrowserModel` so it can be tested: the model needs a
/// `Host`, a `SecretStore` and a `ModelContext` to exist at all, and standing
/// a SwiftData stack up in a unit test is how the suite ends up hanging.
nonisolated struct FileSortOrder: Equatable {
    private(set) var field: FileSort
    private(set) var ascending: Bool

    static let fieldKey = "sftp.sortField"
    static let ascendingKey = "sftp.sortAscending"

    init(field: FileSort = .name, ascending: Bool? = nil) {
        self.field = field
        self.ascending = ascending ?? field.defaultAscending
    }

    /// Restores what was last chosen, falling back to name order.
    init(reading defaults: UserDefaults) {
        let stored = defaults.string(forKey: Self.fieldKey)
            .flatMap(FileSort.init(rawValue:)) ?? .name
        // `object(forKey:)` rather than `bool(forKey:)`: the latter cannot tell
        // "never chosen" from "chosen false", so a saved newest-first would
        // come back as oldest-first on the next launch.
        self.init(field: stored,
                  ascending: defaults.object(forKey: Self.ascendingKey) as? Bool)
    }

    /// Picks a field, or flips the arrow when the active field is chosen again
    /// — the Files.app gesture, and the only way to reach oldest-first.
    mutating func select(_ field: FileSort) {
        if field == self.field {
            ascending.toggle()
        } else {
            self.field = field
            // A new field brings its own useful direction with it. Someone who
            // picks Date wants newest first; making them flip the arrow every
            // time would be a second tap for no reason.
            ascending = field.defaultAscending
        }
    }

    func save(to defaults: UserDefaults) {
        defaults.set(field.rawValue, forKey: Self.fieldKey)
        defaults.set(ascending, forKey: Self.ascendingKey)
    }

    func applied(to files: [RemoteFile]) -> [RemoteFile] {
        RemoteFile.sorted(files, by: field, ascending: ascending)
    }
}
