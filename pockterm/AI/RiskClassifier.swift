import Foundation

enum CommandRisk: Equatable { case readOnly, mutating }

/// Conservative shell-command risk heuristic for the agent's
/// "confirm risky only" mode. Read-only requires every pipeline segment to
/// start with an allowlisted binary and the whole command to be free of
/// redirection, command substitution, and sudo. Anything unknown is mutating.
///
/// A wrong `.mutating` answer only costs the user a confirmation tap, so every
/// ambiguous case fails closed. In particular, binaries that embed a scripting
/// language or exec an arbitrary argv — `awk`, `sed`, `env`, `man`, `less` —
/// are deliberately absent from the allowlist: `awk 'BEGIN{system("…")}'` and
/// `env rm -rf ~` both look read-only from the first word alone.
enum RiskClassifier {
    private static let readOnlyBinaries: Set<String> = [
        "ls", "cat", "head", "tail", "grep", "egrep", "fgrep", "rg",
        "find", "ps", "top", "df", "du", "free", "uname", "whoami", "id",
        "pwd", "echo", "printf", "stat", "file", "wc", "which", "whereis",
        "uptime", "date", "printenv", "hostname", "dig", "nslookup",
        "ping", "netstat", "ss", "journalctl", "dmesg", "history",
        "sort", "uniq", "cut", "tr", "column", "diff", "git",
    ]

    /// Sequences that let a command run something other than the binary it
    /// appears to name: redirection, command and process substitution.
    private static let substitutionMarkers = [">", "<", "`", "$("]

    /// `find` predicates that execute a program or write a file. Matched by
    /// prefix so `-execdir` and `-fprintf` are caught alongside `-exec`.
    private static let findEscapePrefixes = ["-exec", "-ok", "-delete", "-fprint", "-fls"]

    /// The only `git` subcommands treated as read-only. An allowlist, because
    /// git's surface is far too large to denylist safely.
    private static let readOnlyGitSubcommands: Set<String> = [
        "status", "log", "diff", "show", "blame", "describe", "shortlog",
        "reflog", "grep", "ls-files", "ls-tree", "rev-parse", "cat-file",
        "whatchanged", "count-objects",
    ]

    static func classify(_ command: String) -> CommandRisk {
        if command.contains("sudo") { return .mutating }
        if substitutionMarkers.contains(where: command.contains) { return .mutating }

        // Split into pipeline/sequence segments; every one must be read-only.
        let segments = command
            .components(separatedBy: CharacterSet(charactersIn: ";|&\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else { return .mutating }

        for segment in segments {
            let words = segment.split(separator: " ").map(String.init)
            guard let binary = words.first,
                  readOnlyBinaries.contains(binary) else { return .mutating }
            let arguments = words.dropFirst()

            switch binary {
            case "git":
                guard isReadOnlyGit(Array(arguments)) else { return .mutating }
            case "find":
                if arguments.contains(where: { argument in
                    findEscapePrefixes.contains(where: argument.hasPrefix)
                }) { return .mutating }
            default:
                break
            }
        }
        return .readOnly
    }

    /// `git` counts as read-only only when it carries no pre-subcommand flag —
    /// `git -c core.pager='…' log` runs the pager as an arbitrary command — and
    /// the subcommand itself is on the allowlist.
    private static func isReadOnlyGit(_ arguments: [String]) -> Bool {
        guard let subcommand = arguments.first, !subcommand.hasPrefix("-") else { return false }
        return readOnlyGitSubcommands.contains(subcommand)
    }
}
