import Citadel
import Foundation

/// Readable text for a failed SFTP operation.
///
/// Citadel's status error carries the server's own reason ("Permission
/// denied"), but it isn't a LocalizedError, so `localizedDescription` came out
/// as "The operation couldn't be completed. (Citadel.SFTPMessage.Status error
/// 1.)". This pulls the reason back out.
enum SFTPErrorText {
    static func describe(_ error: Error) -> String {
        if let status = error as? SFTPMessage.Status {
            return describe(code: status.errorCode, message: status.message)
        }
        return error.localizedDescription
    }

    /// The server's reason when it gave one, otherwise a plain sentence for
    /// the status code. The server's text is shown as sent, untranslated,
    /// because it is the server talking.
    static func describe(code: SFTPStatusCode, message: String) -> String {
        let reason = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !reason.isEmpty { return reason }
        switch code {
        case .permissionDenied:
            return String(localized: "Permission denied.")
        case .noSuchFile:
            return String(localized: "There's no such file or folder.")
        case .noConnection, .connectionLost:
            return String(localized: "The connection to the server was lost.")
        default:
            return String(localized: "The server refused the request.")
        }
    }
}
