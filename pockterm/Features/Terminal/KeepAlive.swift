import Foundation

/// One selectable keep-alive hold-time.
struct KeepAliveOption: Identifiable {
    let seconds: Int
    let label: String
    var id: Int { seconds }
}

/// Pure keep-alive policy: the selectable hold-times, the fixed probe
/// interval, and the idle-disconnect rule. No UIKit/SwiftData coupling.
enum KeepAlive {
    /// Seconds between keep-alive probes while a session is idle.
    static let interval = 60

    static let options: [KeepAliveOption] = [
        KeepAliveOption(seconds: 0, label: "Off"),
        KeepAliveOption(seconds: 300, label: "5 min"),
        KeepAliveOption(seconds: 900, label: "15 min"),
        KeepAliveOption(seconds: 1800, label: "30 min"),
        KeepAliveOption(seconds: 3600, label: "60 min"),
    ]

    static func label(for seconds: Int) -> String {
        options.first { $0.seconds == seconds }?.label ?? "Off"
    }

    /// True when an idle session has reached its hold-time and should close.
    /// `holdSeconds == 0` (Off) never disconnects.
    static func shouldIdleDisconnect(idleSeconds: Int, holdSeconds: Int) -> Bool {
        holdSeconds > 0 && idleSeconds >= holdSeconds
    }
}
