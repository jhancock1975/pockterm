import Foundation
import SwiftData

/// When the agent must ask before executing a tool call.
enum AgentApproval: String, CaseIterable, Identifiable {
    case always, risky, never
    var id: String { rawValue }
    var label: String {
        switch self {
        case .always: return "Confirm everything"
        case .risky: return "Confirm risky only"
        case .never: return "Auto-run"
        }
    }
}

/// The assistant's configuration: which provider to talk to and with which
/// model. A single row; API keys live in the Keychain, never here.
@Model final class AISettings {
    var activeProviderRaw: String
    var model: String
    // Stored default keeps SwiftData's lightweight migration happy.
    var agentApprovalRaw: String = AgentApproval.always.rawValue

    init(provider: AIProvider = .anthropic, model: String? = nil) {
        self.activeProviderRaw = provider.rawValue
        self.model = model ?? provider.defaultModel
    }

    var activeProvider: AIProvider {
        get { AIProvider(rawValue: activeProviderRaw) ?? .anthropic }
        set { activeProviderRaw = newValue.rawValue }
    }

    var agentApproval: AgentApproval {
        get { AgentApproval(rawValue: agentApprovalRaw) ?? .always }
        set { agentApprovalRaw = newValue.rawValue }
    }

    /// The one true settings row: multiple call sites used to race to create
    /// their own, and unordered `.first` reads could then disagree about which
    /// row was authoritative. This dedupes and returns a stable row.
    static func single(in context: ModelContext) -> AISettings {
        let rows = (try? context.fetch(FetchDescriptor<AISettings>())) ?? []
        if let first = rows.first {
            for extra in rows.dropFirst() { context.delete(extra) }
            if rows.count > 1 { try? context.save() }
            return first
        }
        let created = AISettings()
        context.insert(created)
        try? context.save()
        return created
    }
}
