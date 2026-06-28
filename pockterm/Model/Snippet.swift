import Foundation
import SwiftData

/// A reusable command that can be run into a live terminal session.
@Model final class Snippet {
    var id: UUID
    var label: String
    var command: String
    init(id: UUID = UUID(), label: String, command: String) {
        self.id = id
        self.label = label
        self.command = command
    }
}
