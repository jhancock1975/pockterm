import Foundation

/// What the glasses show. One pure rule, so it can be tested without a
/// display attached.
enum GlassesContent: Equatable {
    case idle
    case terminal(UUID)

    /// The terminal appears on the primary display exactly when it would be on
    /// the phone's screen: a live session, not minimized. Everything else (no
    /// sessions, minimized, a second display) gets the idle screen.
    static func resolve(isPrimary: Bool, activeID: UUID?, sessionIDs: [UUID],
                        isMinimized: Bool) -> GlassesContent {
        guard isPrimary, !isMinimized, let activeID, sessionIDs.contains(activeID) else {
            return .idle
        }
        return .terminal(activeID)
    }
}

/// The terminal's text size on the glasses. It's one app-wide value, kept
/// apart from the phone's pinch zoom because the two screens want very
/// different sizes. 18pt on a 1920×1080 display gives 174×49 (measured).
enum GlassesTextSize {
    static let defaultSize = 18
    static let key = "glassesFontSize"

    static func clamped(_ size: Int) -> Int {
        min(TerminalZoom.maxSize, max(TerminalZoom.minSize, size))
    }

    static func load(from defaults: UserDefaults = .standard) -> Int {
        let stored = defaults.integer(forKey: key)   // 0 when never set
        return stored == 0 ? defaultSize : clamped(stored)
    }

    static func save(_ size: Int, to defaults: UserDefaults = .standard) {
        defaults.set(clamped(size), forKey: key)
    }
}
