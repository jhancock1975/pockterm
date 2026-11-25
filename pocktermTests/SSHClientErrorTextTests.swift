import Testing
import Citadel
@testable import pockterm

/// A refused login must say what to check, not "SSHClientError error 4".
@Test func refusedLoginSaysWhatToCheck() {
    let text = (SSHClientError.allAuthenticationOptionsFailed as Error).localizedDescription
    #expect(text.contains("username"))
    #expect(text.contains("authorized_keys"))
    #expect(!text.contains("Citadel"))
}

@Test func everyClientErrorHasItsOwnText() {
    let all: [SSHClientError] = [.unsupportedPasswordAuthentication, .unsupportedPrivateKeyAuthentication,
                                 .unsupportedHostBasedAuthentication, .channelCreationFailed,
                                 .allAuthenticationOptionsFailed]
    for error in all {
        #expect(!(error as Error).localizedDescription.contains("Citadel"))
    }
}
