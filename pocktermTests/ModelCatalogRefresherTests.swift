import Foundation
import Testing
@testable import pockterm

@Test @MainActor func refreshIsDueOnlyPastStaleWindow() {
    let now = Date.now
    let stamps: [AIProvider: Date] = [.anthropic: now.addingTimeInterval(-25 * 3600),
                                      .openai: now.addingTimeInterval(-1 * 3600)]
    let due = ModelCatalogRefresher.due(keyed: [.anthropic, .openai, .huggingFace],
                                        now: now, lastRefreshed: { stamps[$0] })
    #expect(due == [.anthropic, .huggingFace])  // stale + never-fetched; fresh skipped
}
