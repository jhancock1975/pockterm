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
    var bytesTransferred: Int64 = 0
    var totalBytes: Int64 = 0

    /// `nil` when the server reported no size, so the UI can fall back to an
    /// indeterminate spinner rather than showing a misleading 0%.
    var fractionCompleted: Double? {
        guard totalBytes > 0 else { return nil }
        return min(Double(bytesTransferred) / Double(totalBytes), 1)
    }

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

    func update(_ transfer: Transfer, bytes: Int64, total: Int64) {
        transfer.bytesTransferred = bytes
        transfer.totalBytes = total
    }

    func finish(_ transfer: Transfer, error: Error?) {
        transfer.state = error.map { .failed($0.localizedDescription) } ?? .done
        if error == nil, transfer.totalBytes > 0 {
            transfer.bytesTransferred = transfer.totalBytes
        }
    }

    /// The transfer a progress indicator should track: the oldest still running.
    var active: Transfer? {
        transfers.last { $0.state == .running }
    }
}
