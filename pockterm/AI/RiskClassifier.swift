import Foundation

enum CommandRisk: Equatable { case readOnly, mutating }

/// Conservative shell-command risk heuristic for the agent's
/// "confirm risky only" mode. Read-only requires every pipeline segment to
/// start with an allowlisted binary and the whole command to be free of
/// redirection and sudo. Anything unknown is mutating.
enum RiskClassifier {
    private static let readOnlyBinaries: Set<String> = [
        "ls", "cat", "head", "tail", "less", "grep", "egrep", "fgrep", "rg",
        "find", "ps", "top", "df", "du", "free", "uname", "whoami", "id",
        "pwd", "echo", "printf", "stat", "file", "wc", "which", "whereis",
        "uptime", "date", "env", "printenv", "hostname", "dig", "nslookup",
        "ping", "netstat", "ss", "journalctl", "dmesg", "history", "man",
        "sort", "uniq", "cut", "awk", "sed", "tr", "column", "diff", "git",
    ]
    /// git subcommands that write; everything else on the allowlist is
    /// treated as read-only (status, log, diff, show, branch listing…).
    private static let mutatingGitSubcommands: Set<String> = [
        "push", "commit", "merge", "rebase", "reset", "checkout", "switch",
        "restore", "clean", "stash", "cherry-pick", "revert", "am", "apply",
        "pull", "fetch", "clone", "init", "add", "rm", "mv", "tag", "remote",
    ]

    static func classify(_ command: String) -> CommandRisk {
        if command.contains(">") || command.contains("sudo") { return .mutating }
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
            if binary == "git", let sub = words.dropFirst().first(where: { !$0.hasPrefix("-") }),
               mutatingGitSubcommands.contains(sub) { return .mutating }
            if binary == "find", words.contains(where: { $0 == "-delete" || $0 == "-exec" }) {
                return .mutating
            }
            if binary == "sed", words.contains(where: { $0.hasPrefix("-i") }) {
                return .mutating
            }
        }
        return .readOnly
    }
}
