import Foundation
import Network

/// Reports when the device's network changes under open sessions: Wi-Fi to
/// cellular, a new Wi-Fi network, or the network coming back after none. A
/// TCP connection rarely survives that, and neither end notices until it next
/// tries to talk, so sessions are asked to check themselves.
@MainActor
final class NetworkChangeMonitor {
    var onChange: (() -> Void)?
    private let monitor = NWPathMonitor()
    private var lastSignature: String?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let signature = Self.signature(of: path)
            MainActor.assumeIsolated { self?.update(signature) }
        }
        monitor.start(queue: .main)
    }

    private func update(_ signature: String) {
        defer { lastSignature = signature }
        // The first update only describes where things stand; and there is
        // nothing to reconnect over until the network is back.
        guard let lastSignature, signature != lastSignature, signature != "none" else { return }
        onChange?()
    }

    nonisolated private static func signature(of path: NWPath) -> String {
        guard path.status == .satisfied else { return "none" }
        return path.availableInterfaces.map(\.name).joined(separator: ",")
    }
}
