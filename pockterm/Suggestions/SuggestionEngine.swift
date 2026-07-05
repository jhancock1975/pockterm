import Foundation

struct Suggestion: Equatable {
    enum Kind { case history, snippet, common }
    let text: String
    let kind: Kind
}

/// Prefix-matches the currently typed command against history, snippets, and a
/// built-in common-command list, ranking history first, then snippets, then
/// common. Pure logic so it can be unit-tested independently of the UI.
enum SuggestionEngine {
    static func suggestions(
        prefix: String,
        history: [(command: String, count: Int, lastUsedAt: Date)],
        snippets: [String],
        common: [String],
        limit: Int = 8
    ) -> [Suggestion] {
        guard !prefix.isEmpty else { return [] }

        func matches(_ command: String) -> Bool {
            command.hasPrefix(prefix) && command != prefix
        }

        var ordered: [Suggestion] = []
        var seen = Set<String>()

        func add(_ text: String, _ kind: Suggestion.Kind) {
            guard !seen.contains(text) else { return }
            seen.insert(text)
            ordered.append(Suggestion(text: text, kind: kind))
        }

        let rankedHistory = history
            .filter { matches($0.command) }
            .sorted { lhs, rhs in
                lhs.count != rhs.count ? lhs.count > rhs.count : lhs.lastUsedAt > rhs.lastUsedAt
            }
        for entry in rankedHistory { add(entry.command, .history) }
        for snippet in snippets where matches(snippet) { add(snippet, .snippet) }
        for command in common where matches(command) { add(command, .common) }

        return Array(ordered.prefix(limit))
    }
}
