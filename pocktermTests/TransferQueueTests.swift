import Foundation
import Testing
@testable import pockterm

@Test @MainActor func transferReportsNoFractionWithoutAKnownTotal() {
    let queue = TransferQueue()
    let transfer = queue.start(name: "big.iso", direction: .download)

    // Servers are allowed to omit the size; a 0% bar that never moves would
    // read as a hang, so the UI needs to know the difference.
    queue.update(transfer, bytes: 4096, total: 0)
    #expect(transfer.fractionCompleted == nil)
    #expect(transfer.bytesTransferred == 4096)
}

@Test @MainActor func transferComputesFractionFromBytes() {
    let queue = TransferQueue()
    let transfer = queue.start(name: "big.iso", direction: .download)

    queue.update(transfer, bytes: 25, total: 100)
    #expect(transfer.fractionCompleted == 0.25)

    queue.update(transfer, bytes: 100, total: 100)
    #expect(transfer.fractionCompleted == 1)
}

@Test @MainActor func transferFractionClampsWhenServerUndersizesTheFile() {
    let queue = TransferQueue()
    let transfer = queue.start(name: "grew.log", direction: .download)

    // A file appended to mid-transfer can exceed the size we were told.
    queue.update(transfer, bytes: 150, total: 100)
    #expect(transfer.fractionCompleted == 1)
}

@Test @MainActor func finishingSuccessfullySnapsProgressToComplete() {
    let queue = TransferQueue()
    let transfer = queue.start(name: "a.txt", direction: .upload)
    queue.update(transfer, bytes: 90, total: 100)

    queue.finish(transfer, error: nil)
    #expect(transfer.state == .done)
    #expect(transfer.bytesTransferred == 100)
}

@Test @MainActor func failingLeavesProgressWhereItStopped() {
    let queue = TransferQueue()
    let transfer = queue.start(name: "a.txt", direction: .upload)
    queue.update(transfer, bytes: 90, total: 100)

    queue.finish(transfer, error: CocoaError(.fileNoSuchFile))
    #expect(transfer.bytesTransferred == 90)
    #expect(transfer.state != .done)
}

@Test @MainActor func activeTracksOldestRunningTransfer() {
    let queue = TransferQueue()
    let first = queue.start(name: "first", direction: .download)
    let second = queue.start(name: "second", direction: .download)

    #expect(queue.active?.id == first.id)
    #expect(queue.hasActive)

    queue.finish(first, error: nil)
    #expect(queue.active?.id == second.id)

    queue.finish(second, error: nil)
    #expect(queue.active == nil)
    #expect(!queue.hasActive)
}
