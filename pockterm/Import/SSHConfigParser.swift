import Foundation

struct ParsedHost: Equatable {
    let alias: String
    let hostName: String?
    let user: String?
    let port: Int?
}

/// Minimal `~/.ssh/config` parser. Recognizes `Host` blocks and the
/// `HostName`, `User`, and `Port` keys (case-insensitive). Comments, blank
/// lines, unknown keys, and pure-wildcard `Host *` blocks are ignored.
enum SSHConfigParser {
    static func parse(_ text: String) -> [ParsedHost] {
        var results: [ParsedHost] = []

        var alias: String?
        var hostName: String?
        var user: String?
        var port: Int?

        func flush() {
            guard let alias, !alias.contains("*") else { reset(); return }
            results.append(ParsedHost(alias: alias, hostName: hostName, user: user, port: port))
            reset()
        }
        func reset() {
            alias = nil; hostName = nil; user = nil; port = nil
        }

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            guard parts.count == 2 else { continue }
            let key = parts[0].lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)

            switch key {
            case "host":
                flush()
                alias = value
            case "hostname":
                hostName = value
            case "user":
                user = value
            case "port":
                port = Int(value)
            default:
                continue
            }
        }
        flush()
        return results
    }
}
