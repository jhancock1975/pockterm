import Foundation
import SwiftData

/// A (potentially nested) organizational group. Hosts inherit `defaultIdentity`
/// and `defaultPort` from the nearest ancestor group that defines them.
///
/// Named `HostGroup` (not `Group`) to avoid colliding with SwiftUI's `Group`.
@Model final class HostGroup {
    var id: UUID
    var name: String
    var parent: HostGroup?
    var defaultIdentity: Identity?
    var defaultPort: Int?
    var defaultThemeID: String?
    var defaultFontID: String?
    var defaultFontSize: Int?
    var defaultKeepAliveSeconds: Int?
    var defaultAutoReconnect: Bool?
    var defaultTmuxAttach: Bool?
    init(id: UUID = UUID(), name: String, parent: HostGroup? = nil,
         defaultIdentity: Identity? = nil, defaultPort: Int? = nil,
         defaultThemeID: String? = nil, defaultFontID: String? = nil,
         defaultFontSize: Int? = nil, defaultKeepAliveSeconds: Int? = nil,
         defaultAutoReconnect: Bool? = nil, defaultTmuxAttach: Bool? = nil) {
        self.id = id
        self.name = name
        self.parent = parent
        self.defaultIdentity = defaultIdentity
        self.defaultPort = defaultPort
        self.defaultThemeID = defaultThemeID
        self.defaultFontID = defaultFontID
        self.defaultFontSize = defaultFontSize
        self.defaultKeepAliveSeconds = defaultKeepAliveSeconds
        self.defaultAutoReconnect = defaultAutoReconnect
        self.defaultTmuxAttach = defaultTmuxAttach
    }
}
