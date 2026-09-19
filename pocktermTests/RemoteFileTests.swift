import Testing
import Foundation
@testable import pockterm

@Test @MainActor func kindFromMode() {
    #expect(RemoteFile.kind(fromMode: 0o040755) == .directory)
    #expect(RemoteFile.kind(fromMode: 0o100644) == .regular)
    #expect(RemoteFile.kind(fromMode: 0o120777) == .symlink)
    #expect(RemoteFile.kind(fromMode: 0o010000) == .other)
}

@Test @MainActor func permissionString() {
    #expect(RemoteFile.permissionString(0o755) == "rwxr-xr-x")
    #expect(RemoteFile.permissionString(0o640) == "rw-r-----")
    #expect(RemoteFile.permissionString(0o000) == "---------")
    // Only the low 9 permission bits matter, even with file-type bits set.
    #expect(RemoteFile.permissionString(0o100644) == "rw-r--r--")
}

@Test @MainActor func joinPath() {
    #expect(RemoteFile.joinPath("/a", "b") == "/a/b")
    #expect(RemoteFile.joinPath("/", "b") == "/b")
    #expect(RemoteFile.joinPath("/a/", "b") == "/a/b")
}

// MARK: - modified timestamps

/// Fixed calendar and locale so these assert the *shape* the formatter picks,
/// not the machine's region settings.
private let utc: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()
private let posix = Locale(identifier: "en_US_POSIX")

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
    utc.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

@Test @MainActor func modifiedShowsDateAndTimeForToday() {
    let out = RemoteFile.modifiedString(at(2026, 9, 18, 6, 7),
                                        now: at(2026, 9, 18, 23, 30),
                                        calendar: utc, locale: posix)
    // Today's entries carry the date too. A bare "06:07" is only legible
    // next to other rows that do have a date, which is exactly the listing
    // you cannot count on.
    #expect(out.contains("6:07") || out.contains("06:07"))
    #expect(out.contains("Sep"))
    #expect(out.contains("18"))
}

@Test @MainActor func modifiedShowsDayMonthAndTimeWithinTheYear() {
    let out = RemoteFile.modifiedString(at(2026, 3, 4, 6, 7),
                                        now: at(2026, 9, 18),
                                        calendar: utc, locale: posix)
    #expect(out.contains("Mar"))
    #expect(out.contains("4"))
    #expect(out.contains("6:07") || out.contains("06:07"))
    // The year is implied, so spending width on it would be waste.
    #expect(!out.contains("2026"))
}

@Test @MainActor func modifiedShowsYearOnceItIsAnOldFile() {
    let out = RemoteFile.modifiedString(at(2024, 3, 4, 6, 7),
                                        now: at(2026, 9, 18),
                                        calendar: utc, locale: posix)
    #expect(out.contains("2024"))
    #expect(out.contains("Mar"))
    #expect(out.contains("6:07") || out.contains("06:07"))
}

@Test @MainActor func modifiedTreatsYearBoundaryAsOld() {
    // 31 Dec and 1 Jan are a day apart but must not read as the same year.
    let out = RemoteFile.modifiedString(at(2025, 12, 31, 23, 59),
                                        now: at(2026, 1, 1, 0, 1),
                                        calendar: utc, locale: posix)
    #expect(out.contains("2025"))
    #expect(out.contains("23:59") || out.contains("11:59"))
}

@Test @MainActor func modifiedJoinsDateAndTimeWithoutAConnectorWord() {
    // A single combined format style renders "Sep 18 at 10:44 AM" in English
    // and "18 sept. à 10:44" in French. The row is too tight to pay for that.
    let out = RemoteFile.modifiedString(at(2026, 9, 18, 10, 44),
                                        now: at(2026, 9, 18, 23, 30),
                                        calendar: utc, locale: posix)
    // Not an equality check: ICU separates the AM/PM marker with a narrow
    // no-break space (U+202F), not the ASCII one this file can type.
    #expect(out.hasPrefix("Sep 18 10:44"))
    #expect(!out.contains(" at "))
}
