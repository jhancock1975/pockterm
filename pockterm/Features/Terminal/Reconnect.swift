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

    /// Where the probe found tmux, or nil if it isn't installed. `SSHEngine.exec`
    /// appends `[exit status N]` when the command fails.
    static func tmuxPath(probeOutput: String) -> String? {
        guard !probeOutput.contains("[exit status") else { return nil }
        return probeOutput.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("/") && $0.hasSuffix("tmux") }
    }

    /// The environment variable every shell is opened with, carrying the
    /// session's own id. Anything started in that shell inherits it, a tmux
    /// client included, which is how the app tells which tmux session it was
    /// in, even one the user attached to by hand. `LC_*` because that is what
    /// sshd accepts by default (macOS, Debian, Ubuntu); a server that refuses
    /// it just loses the follow-me reattach.
    static let tagName = "LC_POCKTERM"

    /// Prints the tmux session holding the client started from the shell
    /// tagged `tag`, or nothing. Reads each client's environment from /proc
    /// on Linux and from `ps -E` on macOS and the BSDs. Run through /bin/sh,
    /// whatever the user's login shell is.
    static func trackCommand(tmuxPath: String, tag: String) -> String {
        let want = shellQuote("\(tagName)=\(tag)")
        let script = """
        \(shellQuote(tmuxPath)) list-clients -F '#{client_pid} #{session_name}' 2>/dev/null | \
        while read -r pid name; do \
        if [ -r "/proc/$pid/environ" ]; then tr '\\0' '\\n' < "/proc/$pid/environ" | grep -qxF \(want); \
        else ps -Eww -p "$pid" -o command= 2>/dev/null | tr ' ' '\\n' | grep -qxF \(want); fi \
        && { printf '%s\\n' "$name"; break; }; done
        """
        return "/bin/sh -c \(shellQuote(script))"
    }

    /// The session name in the track command's output, or nil when the shell
    /// is not inside tmux.
    static func trackedSession(output: String) -> String? {
        guard !output.contains("[exit status") else { return nil }
        let name = output.split(separator: "\n").first.map(String.init) ?? ""
        return name.isEmpty ? nil : name
    }

    /// Typed into the new shell after a reconnect to go back to `session`.
    /// `=` makes tmux match the name exactly rather than as a prefix.
    static func attachCommand(session: String) -> String {
        "tmux attach -t \(shellQuote("=" + session))"
    }

    /// Exits 0 only if `session` exists (exact name). Read-only.
    static func hasSessionCommand(tmuxPath: String, session: String) -> String {
        "\(shellQuote(tmuxPath)) has-session -t \(shellQuote("=" + session))"
    }

    /// Whether the session is there, from `hasSessionCommand`'s output.
    static func sessionExists(hasSessionOutput: String) -> Bool {
        !hasSessionOutput.contains("[exit status")
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
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
