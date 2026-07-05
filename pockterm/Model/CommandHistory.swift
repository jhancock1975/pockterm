import Foundation
import SwiftData

/// A command the user has run on a host, used to rank suggestions.
@Model final class CommandHistory {
    var id: UUID
    var hostID: UUID
    var command: String
    var lastUsedAt: Date
    var count: Int

    init(id: UUID = UUID(), hostID: UUID, command: String,
         lastUsedAt: Date = .now, count: Int = 1) {
        self.id = id
        self.hostID = hostID
        self.command = command
        self.lastUsedAt = lastUsedAt
        self.count = count
    }
}
