import Foundation

/// What to do when an upload's name is already taken in the folder.
enum UploadConflictChoice {
    case replace
    case keepBoth
}

/// Where each file of an upload lands. SFTP's open-for-write truncates, so
/// without this an upload silently overwrites whatever shares its name, and
/// phone photos share names all the time (IMG_0001.HEIC).
enum UploadNaming {
    /// Finder's rule: "name 2.ext", then "name 3.ext", skipping any taken.
    /// Only the last extension moves, and a dotfile has none.
    static func uniqueName(for name: String, avoiding taken: Set<String>) -> String {
        guard taken.contains(name) else { return name }
        let ext = (name as NSString).pathExtension
        let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var number = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
            if !taken.contains(candidate) { return candidate }
            number += 1
        }
    }

    /// The names a batch lands under in a folder already holding `existing`.
    /// Replace keeps a clashing name, which overwrites what was there. Either
    /// way, two files of the same batch never land on the same name.
    static func remoteNames(for names: [String], existing: Set<String>,
                            choice: UploadConflictChoice) -> [String] {
        var taken = choice == .keepBoth ? existing : []
        return names.map { name in
            let landed = uniqueName(for: name, avoiding: taken)
            taken.insert(landed)
            return landed
        }
    }

    /// The picked names that already exist, once each, in pick order.
    static func conflicts(_ names: [String], existing: Set<String>) -> [String] {
        var seen: Set<String> = []
        return names.filter { existing.contains($0) && seen.insert($0).inserted }
    }
}
