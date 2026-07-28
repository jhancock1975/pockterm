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
    let themeID: String
    let fontID: String
    let fontSize: Int

    /// The pure inheritance rule, generic over the identity type so tests can
    /// exercise it with plain values: walking real @Model relationships in
    /// tests has hung the test host inside SwiftData's keypath machinery on
    /// the iOS 26.5 simulator (profiled 2026-07-07).
    /// `chain` is the host's ancestor groups, nearest first.
    static func resolve<ID>(hostPort: Int, hostIdentity: ID?,
                            chain: [(port: Int?, identity: ID?)]) -> (port: Int, identity: ID?) {
        let port = hostPort != 0 ? hostPort : (chain.compactMap { $0.port }.first ?? 22)
        let identity = hostIdentity ?? chain.compactMap { $0.identity }.first
        return (port, identity)
    }

    /// Pure appearance inheritance, mirroring `resolve(hostPort:…)`: a non-nil
    /// host value wins; else the nearest ancestor group that defines it; else a
    /// built-in default. `chain` is the host's ancestor groups, nearest first.
    static func resolveAppearance(
        hostTheme: String?, hostFont: String?, hostSize: Int,
        chain: [(theme: String?, font: String?, size: Int?)]
    ) -> (theme: String, font: String, size: Int) {
        let theme = hostTheme ?? chain.compactMap { $0.theme }.first ?? "default"
        let font = hostFont ?? chain.compactMap { $0.font }.first ?? "system"
        let size = hostSize != 0 ? hostSize : (chain.compactMap { $0.size }.first ?? 12)
        return (theme, font, size)
    }

    /// Pure keep-alive inheritance: host value wins (non-zero), else nearest
    /// ancestor group that sets it, else the global default (non-zero), else
    /// Off. `chain` is the host's ancestor groups nearest-first; `0`/`nil`
    /// mean "inherit / not set".
    static func resolveKeepAlive(hostValue: Int, chain: [Int?], globalDefault: Int) -> Int {
        if hostValue != 0 { return hostValue }
        if let group = chain.compactMap({ $0 }).first { return group }
        return globalDefault != 0 ? globalDefault : 0
    }

    @MainActor
    static func resolve(host: Host) -> EffectiveHostSettings {
        var portIdentityChain: [(port: Int?, identity: Identity?)] = []
        var appearanceChain: [(theme: String?, font: String?, size: Int?)] = []
        var group = host.group
        while let g = group {
            portIdentityChain.append((g.defaultPort, g.defaultIdentity))
            appearanceChain.append((g.defaultThemeID, g.defaultFontID, g.defaultFontSize))
            group = g.parent
        }
        let resolved = resolve(hostPort: host.port, hostIdentity: host.identity,
                               chain: portIdentityChain)
        let appear = resolveAppearance(hostTheme: host.themeID, hostFont: host.fontID,
                                       hostSize: host.fontSize, chain: appearanceChain)
        return EffectiveHostSettings(port: resolved.port, identity: resolved.identity,
                                     themeID: appear.theme, fontID: appear.font,
                                     fontSize: appear.size)
    }

    @MainActor
    static func resolveKeepAlive(host: Host, globalDefault: Int) -> Int {
        var chain: [Int?] = []
        var group = host.group
        while let g = group {
            chain.append(g.defaultKeepAliveSeconds)
            group = g.parent
        }
        return resolveKeepAlive(hostValue: host.keepAliveSeconds, chain: chain,
                                globalDefault: globalDefault)
    }
}
