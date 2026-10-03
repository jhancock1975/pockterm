import Foundation
import Observation

/// The external screens iOS has handed the app: video glasses, a TV or a
/// monitor (iOS can't tell them apart). The first one attached shows the
/// terminal and any others show the idle screen. Scene delegates register
/// here, and everything that behaves differently in glasses mode keys off
/// `isConnected`.
@MainActor
@Observable
final class ExternalDisplay {
    private var scenes: [ObjectIdentifier] = []

    /// Called when the first display arrives (true) and when the last one
    /// leaves (false). AppContainer points this at the session manager.
    @ObservationIgnored var onConnectionChange: ((Bool) -> Void)?

    var isConnected: Bool { !scenes.isEmpty }

    /// Whether this scene is the one that shows the terminal.
    func isPrimary(_ scene: ObjectIdentifier) -> Bool { scenes.first == scene }

    func attach(_ scene: ObjectIdentifier) {
        guard !scenes.contains(scene) else { return }
        let wasConnected = isConnected
        scenes.append(scene)
        if !wasConnected { onConnectionChange?(true) }
    }

    func detach(_ scene: ObjectIdentifier) {
        guard let index = scenes.firstIndex(of: scene) else { return }
        scenes.remove(at: index)
        if !isConnected { onConnectionChange?(false) }
    }
}
