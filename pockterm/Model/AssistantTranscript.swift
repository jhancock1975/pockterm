import Foundation
import SwiftData

/// One persisted turn of an assistant conversation.
///
/// Keyed by the host's `UUID` rather than by a SwiftData relationship to
/// `Host`. That is deliberate: walking `@Model` relationships stalls the main
/// thread for minutes in this project's unit tests, so the transcript layer is
/// relationship-free and its logic stays testable as plain values.
///
/// Every property has a default so SwiftData's lightweight migration can add
/// this entity to an existing store without a migration plan.
@Model
final class AssistantMessageRecord {
    /// `Host.id` of the conversation this turn belongs to.
    var hostID: UUID = UUID()
    /// Position within the conversation. Fetches sort on this rather than on
    /// `createdAt`, which can tie when a turn is written in a single run loop.
    var sequence: Int = 0
    var roleRaw: String = AssistantMessage.Role.user.rawValue
    var text: String = ""
    var toolName: String?
    var toolDetail: String?
    var toolResult: String?
    var denied: Bool = false
    var createdAt: Date = Date.distantPast

    init(hostID: UUID, sequence: Int, message: AssistantMessage, createdAt: Date = .now) {
        self.hostID = hostID
        self.sequence = sequence
        self.roleRaw = message.role.rawValue
        self.text = message.text
        self.toolName = message.toolName
        self.toolDetail = message.toolDetail
        self.toolResult = message.toolResult
        self.denied = message.denied
        self.createdAt = createdAt
    }

    /// Back to the in-memory turn the UI renders.
    var message: AssistantMessage {
        var value = AssistantMessage(role: AssistantMessage.Role(rawValue: roleRaw) ?? .user,
                                     text: text)
        value.toolName = toolName
        value.toolDetail = toolDetail
        value.toolResult = toolResult
        value.denied = denied
        return value
    }
}

/// Loads and stores one host's conversation.
///
/// Saving rewrites the host's turns rather than diffing them. A transcript is
/// capped at `AssistantTranscript.maxTurns` and written once per completed
/// turn, so the cost is trivial next to the network call that preceded it, and
/// it cannot drift out of step with what is on screen.
@MainActor
struct AssistantTranscriptStore {
    let modelContext: ModelContext

    func load(hostID: UUID) -> [AssistantMessage] {
        var descriptor = FetchDescriptor<AssistantMessageRecord>(
            predicate: #Predicate { $0.hostID == hostID },
            sortBy: [SortDescriptor(\.sequence)])
        descriptor.fetchLimit = AssistantTranscript.maxTurns
        let records = (try? modelContext.fetch(descriptor)) ?? []
        return records.map(\.message)
    }

    func save(_ messages: [AssistantMessage], hostID: UUID) {
        clear(hostID: hostID)
        let keep = AssistantTranscript.pruned(AssistantTranscript.persistable(messages))
        for (index, message) in keep.enumerated() {
            modelContext.insert(AssistantMessageRecord(hostID: hostID,
                                                       sequence: index,
                                                       message: message))
        }
        try? modelContext.save()
    }

    func clear(hostID: UUID) {
        try? modelContext.delete(model: AssistantMessageRecord.self,
                                 where: #Predicate { $0.hostID == hostID })
    }
}

/// Pure transcript rules, factored out so they can be tested without SwiftData.
enum AssistantTranscript {
    /// Turns kept per host. A transcript holds terminal output and tool
    /// results, so it grows much faster than a chat log and is capped rather
    /// than left to accumulate on the device indefinitely.
    static let maxTurns = 200

    /// The tail that gets stored, oldest first.
    ///
    /// Trimming from the front rather than the back: the recent exchange is
    /// what a user returns to, and the model is re-sent context from the live
    /// terminal on every turn anyway, so old turns earn their keep least.
    static func pruned(_ messages: [AssistantMessage], limit: Int = maxTurns) -> [AssistantMessage] {
        guard limit > 0 else { return [] }
        guard messages.count > limit else { return messages }
        return Array(messages.suffix(limit))
    }

    /// Turns worth writing to disk.
    ///
    /// An empty assistant turn is the placeholder `send` appends before the
    /// first token arrives; persisting it would reload as a blank bubble. A
    /// tool turn with no result is one that never finished — usually because
    /// the app went away mid-call — and reloading it would strand a spinner.
    static func persistable(_ messages: [AssistantMessage]) -> [AssistantMessage] {
        messages.filter { message in
            switch message.role {
            case .user:      return !message.text.isEmpty
            case .assistant: return !message.text.isEmpty
            case .tool:      return message.denied || message.toolResult != nil
            }
        }
    }
}
