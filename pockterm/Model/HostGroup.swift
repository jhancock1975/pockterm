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
    init(id: UUID = UUID(), name: String, parent: HostGroup? = nil,
         defaultIdentity: Identity? = nil, defaultPort: Int? = nil) {
        self.id = id
        self.name = name
        self.parent = parent
        self.defaultIdentity = defaultIdentity
        self.defaultPort = defaultPort
    }
}
