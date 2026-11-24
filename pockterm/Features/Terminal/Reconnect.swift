import Foundation

/// The rules behind auto-reconnect, kept as plain values so they can be tested
/// without a server. `TerminalSession` does the connecting; this decides when,
/// how often, and when to stop.
enum Reconnect {
    /// The wait before each attempt, in seconds. Fast at first, because most
    /// drops are an app switch or a network handover that is already over,
    /// then capped so a server that is down for a reboot is not hammered.
    /// About three minutes in all before giving up.
    static let delays: [Int] = [1, 2, 4, 8, 15, 30, 30, 30, 30, 30]

    /// The wait before attempt `attempt` (1-based), or nil once every attempt
    /// has been spent and the session should show the manual Reconnect button.
    static func delay(beforeAttempt attempt: Int) -> Duration? {
        guard attempt >= 1, attempt <= delays.count else { return nil }
        return .seconds(delays[attempt - 1])
    }

    /// Attaches to the tmux session `pockterm`, or creates it.
    static let tmuxCommand = "tmux new -A -s pockterm"

    /// Asks the host where tmux is, through the user's login shell. A plain
    /// exec channel gets a bare PATH, which misses tmux wherever it is set up
    /// in a login profile, such as Homebrew's /opt/homebrew/bin on a Mac.
    static let tmuxProbeCommand = #""${SHELL:-sh}" -lc 'command -v tmux'"#

    /// Whether the probe's output says tmux is installed. `SSHEngine.exec`
    /// appends `[exit status N]` when the command fails.
    static func tmuxAvailable(probeOutput: String) -> Bool {
        !probeOutput.contains("[exit status") && probeOutput.contains("tmux")
    }

    /// What to do once the shell has ended.
    enum Response: Equatable {
        /// Start reconnecting.
        case reconnect
        /// The connection dropped and reconnecting is off for this host.
        case showConnectionLost
        /// The remote shell ended on its own, for example by `exit`.
        case showClosed
        /// The session was already on its way down; leave it be.
        case ignore
    }

    /// `wasConnected` is whether the session was live when the shell ended.
    /// Anything else — the user disconnected, the session was idle-closed, or
    /// a reconnect is already under way — is not a fresh drop.
    static func response(to end: ShellEnd, wasConnected: Bool,
                         userDisconnected: Bool, autoReconnect: Bool) -> Response {
        guard wasConnected, !userDisconnected else { return .ignore }
        switch end {
        case .exited: return .showClosed
        case .connectionLost: return autoReconnect ? .reconnect : .showConnectionLost
        }
    }
}
