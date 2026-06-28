import Foundation

enum TransferDirection {
    case upload
    case download
}

/// One file transfer's lifecycle, observed by the UI.
@MainActor
@Observable
final class Transfer: Identifiable {
    enum State: Equatable {
        case running
        case done
        case failed(String)
    }

    let id = UUID()
    let name: String
    let direction: TransferDirection
    var state: State = .running

    init(name: String, direction: TransferDirection) {
        self.name = name
        self.direction = direction
    }
}

/// Tracks active and recent transfers for display in the files browser.
@MainActor
@Observable
final class TransferQueue {
    var transfers: [Transfer] = []

    var hasActive: Bool { transfers.contains { $0.state == .running } }

    @discardableResult
    func start(name: String, direction: TransferDirection) -> Transfer {
        let transfer = Transfer(name: name, direction: direction)
        transfers.insert(transfer, at: 0)
        return transfer
    }

    func finish(_ transfer: Transfer, error: Error?) {
        transfer.state = error.map { .failed($0.localizedDescription) } ?? .done
    }

    func clearCompleted() {
        transfers.removeAll { $0.state != .running }
    }
}
