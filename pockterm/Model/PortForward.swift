import Foundation
import SwiftData

enum ForwardType: String, Codable {
    case local
    case remote
    case dynamic
}

/// A configured SSH tunnel. For `dynamic` (SOCKS5) forwards, `remoteHost`/
/// `remotePort` are unused — the target comes from each SOCKS request.
@Model final class PortForward {
    var id: UUID
    var label: String
    var typeRaw: String
    var bindPort: Int
    var remoteHost: String
    var remotePort: Int
    var host: Host?

    var type: ForwardType {
        get { ForwardType(rawValue: typeRaw) ?? .local }
        set { typeRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), label: String, type: ForwardType, bindPort: Int,
         remoteHost: String = "", remotePort: Int = 0, host: Host? = nil) {
        self.id = id
        self.label = label
        self.typeRaw = type.rawValue
        self.bindPort = bindPort
        self.remoteHost = remoteHost
        self.remotePort = remotePort
        self.host = host
    }
}
