import Testing
@testable import pockterm

// MARK: - Finder-style names

@Test @MainActor func aFreeNameIsKept() {
    #expect(UploadNaming.uniqueName(for: "notes.txt", avoiding: ["other.txt"]) == "notes.txt")
}

@Test @MainActor func aTakenNameGetsTwoBeforeTheExtension() {
    #expect(UploadNaming.uniqueName(for: "IMG_0001.HEIC", avoiding: ["IMG_0001.HEIC"])
            == "IMG_0001 2.HEIC")
}

@Test @MainActor func takenSuffixesAreSkipped() {
    #expect(UploadNaming.uniqueName(for: "a.txt", avoiding: ["a.txt", "a 2.txt"]) == "a 3.txt")
}

@Test @MainActor func aNameWithoutAnExtensionGetsTwoOnTheEnd() {
    #expect(UploadNaming.uniqueName(for: "notes", avoiding: ["notes"]) == "notes 2")
}

@Test @MainActor func aDotfileKeepsItsDot() {
    // ".bashrc" has no extension: "bashrc" is the name, not the type.
    #expect(UploadNaming.uniqueName(for: ".bashrc", avoiding: [".bashrc"]) == ".bashrc 2")
}

@Test @MainActor func onlyTheLastExtensionMoves() {
    #expect(UploadNaming.uniqueName(for: "archive.tar.gz", avoiding: ["archive.tar.gz"])
            == "archive.tar 2.gz")
}

// MARK: - Batches

@Test @MainActor func keepBothRenamesOnlyTheClashes() {
    #expect(UploadNaming.remoteNames(for: ["a.txt", "b.txt"], existing: ["a.txt"],
                                     choice: .keepBoth) == ["a 2.txt", "b.txt"])
}

@Test @MainActor func replaceKeepsTheClashingNames() {
    #expect(UploadNaming.remoteNames(for: ["a.txt", "b.txt"], existing: ["a.txt"],
                                     choice: .replace) == ["a.txt", "b.txt"])
}

@Test @MainActor func twoUploadsInOneBatchNeverShareAName() {
    // Replace means "overwrite what was already there", never "let the second
    // file of this batch overwrite the first".
    #expect(UploadNaming.remoteNames(for: ["a.txt", "a.txt"], existing: [],
                                     choice: .replace) == ["a.txt", "a 2.txt"])
    #expect(UploadNaming.remoteNames(for: ["a.txt", "a.txt"], existing: ["a.txt"],
                                     choice: .keepBoth) == ["a 2.txt", "a 3.txt"])
}

@Test @MainActor func clashesAreListedOnceInPickOrder() {
    #expect(UploadNaming.conflicts(["b.txt", "a.txt", "b.txt"], existing: ["a.txt", "b.txt"])
            == ["b.txt", "a.txt"])
}

@Test @MainActor func noClashesMeansNothingToAsk() {
    #expect(UploadNaming.conflicts(["new.txt"], existing: ["a.txt"]).isEmpty)
}
