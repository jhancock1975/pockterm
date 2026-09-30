import Testing
import Foundation
import Citadel
@testable import pockterm

@Test @MainActor func theServersOwnReasonIsShown() {
    #expect(SFTPErrorText.describe(code: .permissionDenied, message: "Permission denied")
            == "Permission denied")
}

@Test @MainActor func aBlankReasonFallsBackToTheStatusCode() {
    #expect(SFTPErrorText.describe(code: .permissionDenied, message: "  ") == "Permission denied.")
    #expect(SFTPErrorText.describe(code: .noSuchFile, message: "") == "There's no such file or folder.")
    #expect(SFTPErrorText.describe(code: .connectionLost, message: "")
            == "The connection to the server was lost.")
}

@Test @MainActor func anUnexplainedRefusalStillSaysSomethingPlain() {
    #expect(SFTPErrorText.describe(code: .unknown(99), message: "")
            == "The server refused the request.")
}

@Test @MainActor func errorsFromElsewherePassThrough() {
    let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "The disk is full."])
    #expect(SFTPErrorText.describe(error) == "The disk is full.")
}
