import Foundation

struct SOCKSTarget: Equatable {
    let host: String
    let port: Int
}

/// Minimal SOCKS5 parsing for the dynamic-forwarding front-end. Only what a
/// CONNECT proxy needs: the no-auth greeting and a CONNECT request.
nonisolated enum SOCKS5 {
    /// Returns true if the client's greeting offers the "no authentication"
    /// method, false if it doesn't, or nil if the bytes are incomplete.
    static func parseGreeting(_ bytes: [UInt8]) -> Bool? {
        guard bytes.count >= 2 else { return nil }
        let count = Int(bytes[1])
        guard bytes.count >= 2 + count else { return nil }
        return bytes[2..<(2 + count)].contains(0x00)
    }

    /// Server reply selecting the no-auth method.
    static let greetingReply: [UInt8] = [0x05, 0x00]

    /// Parses a CONNECT request into its target, or nil if incomplete/unsupported.
    static func parseConnect(_ bytes: [UInt8]) -> SOCKSTarget? {
        guard bytes.count >= 4 else { return nil }
        guard bytes[0] == 0x05, bytes[1] == 0x01 else { return nil }  // VER 5, CMD CONNECT
        let atyp = bytes[3]

        switch atyp {
        case 0x01:  // IPv4
            guard bytes.count >= 10 else { return nil }
            let host = bytes[4...7].map(String.init).joined(separator: ".")
            let port = Int(bytes[8]) << 8 | Int(bytes[9])
            return SOCKSTarget(host: host, port: port)
        case 0x03:  // domain name
            guard bytes.count >= 5 else { return nil }
            let len = Int(bytes[4])
            guard bytes.count >= 5 + len + 2 else { return nil }
            let host = String(decoding: bytes[5..<(5 + len)], as: UTF8.self)
            let port = Int(bytes[5 + len]) << 8 | Int(bytes[5 + len + 1])
            return SOCKSTarget(host: host, port: port)
        case 0x04:  // IPv6
            guard bytes.count >= 22 else { return nil }
            var groups: [String] = []
            for i in stride(from: 4, to: 20, by: 2) {
                groups.append(String(format: "%x", Int(bytes[i]) << 8 | Int(bytes[i + 1])))
            }
            let port = Int(bytes[20]) << 8 | Int(bytes[21])
            return SOCKSTarget(host: groups.joined(separator: ":"), port: port)
        default:
            return nil
        }
    }

    /// Reply to a CONNECT request (bound address reported as 0.0.0.0:0).
    static func connectReply(success: Bool) -> [UInt8] {
        [0x05, success ? 0x00 : 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
    }
}
