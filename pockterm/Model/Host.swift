import Foundation
import SwiftData

/// What a host opens by default. Both run over the same SSH connection — this
/// only decides whether tapping the host lands you in a terminal or in the
/// file browser. Any host can still reach the other one on demand.
enum HostProtocol: String, CaseIterable, Identifiable {
    case ssh
    case sftp

    var id: String { rawValue }

    /// Shown in the protocol picker and spoken by VoiceOver on the host row,
    /// so it is localized. The protocol names themselves stay verbatim.
    var title: String {
        switch self {
        case .ssh: String(localized: "SSH (Terminal)")
        case .sftp: String(localized: "SFTP (Files)")
        }
    }

    var symbol: String {
        switch self {
        case .ssh: "terminal"
        case .sftp: "folder"
        }
    }
}

@Model final class Host {
    var id: UUID
    var label: String
    var address: String
    var port: Int
    var identity: Identity?
    var startupSnippet: String?
    var group: HostGroup?
    var isFavorite: Bool
    var lastConnectedAt: Date?
    var themeID: String?
    var fontID: String?
    // Inline default required: SwiftData lightweight migration crashes existing stores without it. 0 = inherit sentinel.
    var fontSize: Int = 0
    // Inline default required: SwiftData lightweight migration crashes existing stores without it. 0 = inherit sentinel.
    var keepAliveSeconds: Int = 0
    // Inline default required: SwiftData lightweight migration crashes existing stores without it.
    // Stored raw so an unknown future value degrades to .ssh instead of failing to load.
    var protocolRaw: String = HostProtocol.ssh.rawValue

    var hostProtocol: HostProtocol {
        get { HostProtocol(rawValue: protocolRaw) ?? .ssh }
        set { protocolRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), label: String, address: String, port: Int = 22,
         identity: Identity? = nil, startupSnippet: String? = nil,
         group: HostGroup? = nil, isFavorite: Bool = false, lastConnectedAt: Date? = nil,
         themeID: String? = nil, fontID: String? = nil, fontSize: Int = 0,
         keepAliveSeconds: Int = 0, hostProtocol: HostProtocol = .ssh) {
        self.id = id
        self.label = label
        self.address = address
        self.port = port
        self.identity = identity
        self.startupSnippet = startupSnippet
        self.group = group
        self.isFavorite = isFavorite
        self.lastConnectedAt = lastConnectedAt
        self.themeID = themeID
        self.fontID = fontID
        self.fontSize = fontSize
        self.keepAliveSeconds = keepAliveSeconds
        self.protocolRaw = hostProtocol.rawValue
    }
}
