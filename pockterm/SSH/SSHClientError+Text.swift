import Citadel
import Foundation

/// Readable text for Citadel's login failures.
///
/// `SSHClientError` isn't a LocalizedError, so a refused login came out as
/// "The operation couldn't be completed. (Citadel.SSHClientError error 4.)",
/// which says nothing about what to fix. The usual cause is a username the
/// server doesn't know, or a key that isn't in its authorized_keys, and the
/// server never says which.
extension SSHClientError: @retroactive LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .allAuthenticationOptionsFailed:
            return String(localized: "The server didn't accept this login. Check the identity's username, and that its key is in the server's authorized_keys file or its password is right.")
        case .unsupportedPasswordAuthentication:
            return String(localized: "The server doesn't accept passwords. Use a key instead.")
        case .unsupportedPrivateKeyAuthentication, .unsupportedHostBasedAuthentication:
            return String(localized: "The server doesn't accept this kind of login.")
        case .channelCreationFailed:
            return String(localized: "The server refused to open a session.")
        }
    }
}
