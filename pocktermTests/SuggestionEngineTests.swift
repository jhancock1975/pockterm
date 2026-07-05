import Testing
import Foundation
@testable import pockterm

private func hist(_ command: String, _ count: Int, _ secondsAgo: TimeInterval)
    -> (command: String, count: Int, lastUsedAt: Date) {
    (command, count, Date(timeIntervalSinceNow: -secondsAgo))
}

@Test func ranksHistoryThenSnippetsThenCommon() {
    let result = SuggestionEngine.suggestions(
        prefix: "gi",
        history: [hist("git push", 1, 10), hist("git status", 3, 20)],
        snippets: ["gitk"],
        common: ["git", "grep"])
    #expect(result == [
        Suggestion(text: "git status", kind: .history),   // higher count first
        Suggestion(text: "git push", kind: .history),
        Suggestion(text: "gitk", kind: .snippet),
        Suggestion(text: "git", kind: .common),           // "grep" doesn't match "gi"
    ])
}

@Test func excludesExactPrefixMatch() {
    let result = SuggestionEngine.suggestions(
        prefix: "git",
        history: [hist("git", 5, 1), hist("git status", 2, 2)],
        snippets: [], common: [])
    #expect(result == [Suggestion(text: "git status", kind: .history)])
}

@Test func emptyPrefixReturnsNothing() {
    let result = SuggestionEngine.suggestions(
        prefix: "", history: [hist("ls", 1, 1)], snippets: [], common: ["ls"])
    #expect(result.isEmpty)
}

@Test func dedupesKeepingHistoryOverCommon() {
    let result = SuggestionEngine.suggestions(
        prefix: "l", history: [hist("ls", 3, 1)], snippets: [], common: ["ls", "ls -la"])
    #expect(result == [
        Suggestion(text: "ls", kind: .history),
        Suggestion(text: "ls -la", kind: .common),
    ])
}

@Test func respectsLimit() {
    let result = SuggestionEngine.suggestions(
        prefix: "l", history: [], snippets: [],
        common: ["ls", "ls -la", "less", "ln -s"], limit: 2)
    #expect(result.count == 2)
}
