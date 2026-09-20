import Testing
import Foundation
@testable import pockterm

private let epoch = Date(timeIntervalSince1970: 0)

private func file(_ name: String, _ kind: FileKind = .regular,
                  minutes: Double? = nil) -> RemoteFile {
    RemoteFile(id: "/d/" + name, name: name, kind: kind, size: 0, permissions: 0o644,
               modified: minutes.map { epoch.addingTimeInterval($0 * 60) })
}

private func names(_ files: [RemoteFile]) -> [String] { files.map(\.name) }

// MARK: - ordering

@Test @MainActor func nameSortKeepsDirectoriesFirst() {
    let listing = [file("zeta"), file("alpha"), file("mid", .directory)]
    #expect(names(RemoteFile.sorted(listing, by: .name, ascending: true))
            == ["mid", "alpha", "zeta"])
}

@Test @MainActor func reversedNameSortStillKeepsDirectoriesFirst() {
    // Reversing is meant to flip the alphabet, not to bury the folders at the
    // bottom of the screen.
    let listing = [file("alpha"), file("zeta"), file("mid", .directory)]
    #expect(names(RemoteFile.sorted(listing, by: .name, ascending: false))
            == ["mid", "zeta", "alpha"])
}

@Test @MainActor func nameSortOrdersNumbersTheWayPeopleRead() {
    let listing = [file("take10.mp4"), file("take2.mp4"), file("take1.mp4")]
    #expect(names(RemoteFile.sorted(listing, by: .name, ascending: true))
            == ["take1.mp4", "take2.mp4", "take10.mp4"])
}

@Test @MainActor func dateSortIgnoresKindSoTheNewestThingIsOnTop() {
    // A directory clump at the top would hide the file the sort was for.
    let listing = [file("old-dir", .directory, minutes: 1),
                   file("render.mp4", minutes: 99),
                   file("older.mp4", minutes: 50)]
    #expect(names(RemoteFile.sorted(listing, by: .date, ascending: false))
            == ["render.mp4", "older.mp4", "old-dir"])
}

@Test @MainActor func dateSortAscendingPutsTheOldestFirst() {
    let listing = [file("b", minutes: 99), file("a", minutes: 1)]
    #expect(names(RemoteFile.sorted(listing, by: .date, ascending: true)) == ["a", "b"])
}

@Test @MainActor func undatedEntriesSortLastWhicheverWayTheArrowPoints() {
    // A server that reported no mtime must not win the top of a newest-first
    // listing by default.
    let listing = [file("nodate"), file("dated", minutes: 5)]
    #expect(names(RemoteFile.sorted(listing, by: .date, ascending: false))
            == ["dated", "nodate"])
    #expect(names(RemoteFile.sorted(listing, by: .date, ascending: true))
            == ["dated", "nodate"])
}

@Test @MainActor func equalDatesBreakOnNameSoRefreshesDoNotReshuffle() {
    // Build output shares mtimes constantly, and `sorted(by:)` is not stable.
    let listing = [file("c", minutes: 7), file("a", minutes: 7), file("b", minutes: 7)]
    let once = names(RemoteFile.sorted(listing, by: .date, ascending: false))
    #expect(once == ["a", "b", "c"])
    #expect(names(RemoteFile.sorted(listing.reversed(), by: .date, ascending: false)) == once)
}

@Test @MainActor func namesThatCompareEqualDoNotTrapTheSort() {
    // "é" precomposed vs decomposed: localizedStandardCompare calls them the
    // same, and a comparator claiming a < b AND b < a crashes `sorted(by:)`.
    let listing = [file("caf\u{00E9}.txt"), file("cafe\u{0301}.txt"), file("a.txt")]
    #expect(RemoteFile.sorted(listing, by: .name, ascending: true).count == 3)
    #expect(RemoteFile.sorted(listing, by: .name, ascending: false).count == 3)
}

// MARK: - the choice itself

@Test @MainActor func pickingDateAdoptsNewestFirst() {
    var order = FileSortOrder()
    #expect(order.field == .name)
    #expect(order.ascending)       // A-Z
    order.select(.date)
    #expect(order.field == .date)
    #expect(!order.ascending)      // newest first, without a second tap
}

@Test @MainActor func pickingTheActiveFieldAgainFlipsTheArrow() {
    var order = FileSortOrder()
    order.select(.date)
    order.select(.date)
    #expect(order.field == .date)
    #expect(order.ascending)       // oldest first — only reachable this way
    order.select(.date)
    #expect(!order.ascending)
}

@Test @MainActor func switchingBackToNameDropsTheDateDirection() {
    var order = FileSortOrder()
    order.select(.date)            // now descending
    order.select(.name)
    #expect(order.ascending)       // A-Z, not Z-A
}

// MARK: - remembering it

private func scratchDefaults() -> UserDefaults {
    let suite = UserDefaults(suiteName: "sorttests." + UUID().uuidString)!
    return suite
}

@Test @MainActor func anUnsetPreferenceIsNameOrder() {
    #expect(FileSortOrder(reading: scratchDefaults()) == FileSortOrder(field: .name))
}

@Test @MainActor func theChoiceSurvivesARelaunch() {
    let defaults = scratchDefaults()
    var order = FileSortOrder()
    order.select(.date)
    order.save(to: defaults)
    #expect(FileSortOrder(reading: defaults) == order)
}

@Test @MainActor func aSavedDescendingOrderDoesNotComeBackAscending() {
    // `bool(forKey:)` returns false for a missing key, so reading the stored
    // direction through it would turn newest-first into oldest-first here.
    let defaults = scratchDefaults()
    var order = FileSortOrder()
    order.select(.date)            // date, descending
    order.select(.date)            // date, ASCENDING — the false that must stick
    order.save(to: defaults)
    #expect(FileSortOrder(reading: defaults).ascending)

    var flipped = FileSortOrder(reading: defaults)
    flipped.select(.date)          // back to descending
    flipped.save(to: defaults)
    #expect(!FileSortOrder(reading: defaults).ascending)
}

@Test @MainActor func aStoredFieldNobodyRecognizesFallsBackToName() {
    let defaults = scratchDefaults()
    defaults.set("kind", forKey: FileSortOrder.fieldKey)
    #expect(FileSortOrder(reading: defaults).field == .name)
}
