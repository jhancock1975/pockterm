import Foundation

/// The connection settings actually used for a host after applying group
/// inheritance. A host value wins; otherwise the nearest ancestor group that
/// defines the setting wins; otherwise a built-in default.
///
/// A host `port` of `0` is the sentinel meaning "inherit" (the editor offers
/// this as "Default").
struct EffectiveHostSettings {
    let port: Int
    let identity: Identity?

    @MainActor
    static func resolve(host: Host) -> EffectiveHostSettings {
        let port = host.port != 0 ? host.port : (inheritedPort(from: host.group) ?? 22)
        let identity = host.identity ?? inheritedIdentity(from: host.group)
        return EffectiveHostSettings(port: port, identity: identity)
    }

    @MainActor
    private static func inheritedPort(from group: HostGroup?) -> Int? {
        var current = group
        while let g = current {
            if let p = g.defaultPort { return p }
            current = g.parent
        }
        return nil
    }

    @MainActor
    private static func inheritedIdentity(from group: HostGroup?) -> Identity? {
        var current = group
        while let g = current {
            if let id = g.defaultIdentity { return id }
            current = g.parent
        }
        return nil
    }
}
