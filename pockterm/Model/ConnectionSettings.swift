import Foundation
import SwiftData

/// App-wide connection preferences. A single row. `keepAliveSeconds` is the
/// global default hold-time hosts inherit when they and their groups don't
/// set one. `0` = Off (today's behavior).
@Model final class ConnectionSettings {
    // Inline default keeps SwiftData lightweight migration happy.
    var defaultKeepAliveSeconds: Int = 0

    init(defaultKeepAliveSeconds: Int = 0) {
        self.defaultKeepAliveSeconds = defaultKeepAliveSeconds
    }

    /// Returns the single settings row, deduping any accidental extras.
    static func single(in context: ModelContext) -> ConnectionSettings {
        let rows = (try? context.fetch(FetchDescriptor<ConnectionSettings>())) ?? []
        if let first = rows.first {
            for extra in rows.dropFirst() { context.delete(extra) }
            if rows.count > 1 { try? context.save() }
            return first
        }
        let created = ConnectionSettings()
        context.insert(created)
        try? context.save()
        return created
    }
}
