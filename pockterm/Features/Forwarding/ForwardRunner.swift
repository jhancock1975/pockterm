import Foundation
import SwiftData

/// Owns running tunnels and their live status. Tunnels keep running across tab
/// switches because the runner lives in `AppContainer`.
@MainActor
@Observable
final class ForwardRunner: HostKeyDeciding {
    enum Status: Equatable {
        case stopped
        case connecting
        case active(Int)
        case failed(String)
    }

    private let secretStore: SecretStore
    let modelContext: ModelContext
    private var services: [UUID: PortForwardService] = [:]
    var statuses: [UUID: Status] = [:]
    var pendingHostKey: PendingHostKey?

    init(secretStore: SecretStore, modelContext: ModelContext) {
        self.secretStore = secretStore
        self.modelContext = modelContext
    }

    func status(for forward: PortForward) -> Status { statuses[forward.id] ?? .stopped }

    func isRunning(_ forward: PortForward) -> Bool {
        switch status(for: forward) {
        case .active, .connecting: return true
        case .stopped, .failed: return false
        }
    }

    func toggle(_ forward: PortForward) {
        isRunning(forward) ? stop(forward) : start(forward)
    }

    func start(_ forward: PortForward) {
        guard let host = forward.host else {
            statuses[forward.id] = .failed("This forward has no host.")
            return
        }
        statuses[forward.id] = .connecting
        let service = PortForwardService()
        services[forward.id] = service
        let id = forward.id
        let type = forward.type
        let bindPort = forward.bindPort
        let remoteHost = forward.remoteHost
        let remotePort = forward.remotePort

        Task {
            let creds: SSHCredentials
            switch HostConnection.credentials(for: host, secretStore: secretStore) {
            case .failure(let message):
                statuses[id] = .failed(message); return
            case .success(let resolved):
                creds = resolved
            }
            do {
                try await connectCheckingHostKey { validate in
                    try await service.connect(creds, onHostKey: validate)
                }
                switch type {
                case .local:
                    let bound = try await service.startLocal(bindHost: "127.0.0.1", bindPort: bindPort,
                                                             targetHost: remoteHost, targetPort: remotePort)
                    statuses[id] = .active(bound)
                case .dynamic:
                    let bound = try await service.startDynamic(bindHost: "127.0.0.1", bindPort: bindPort)
                    statuses[id] = .active(bound)
                case .remote:
                    try await service.startRemote(bindPort: bindPort, targetHost: remoteHost, targetPort: remotePort)
                    statuses[id] = .active(bindPort)
                }
            } catch {
                statuses[id] = .failed(error.localizedDescription)
                services[id] = nil
            }
        }
    }

    func stop(_ forward: PortForward) {
        if let service = services[forward.id] {
            Task { await service.stop() }
        }
        services[forward.id] = nil
        statuses[forward.id] = .stopped
    }

}
