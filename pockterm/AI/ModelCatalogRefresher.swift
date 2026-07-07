import Foundation

/// Refreshes providers' model lists at most once per day, triggered when the
/// app launches or returns to the foreground (no timers, no BGTaskScheduler —
/// this is the reliable low-frequency pattern on iOS). Only providers with a
/// stored API key are fetched; failures wait for the next foreground pass.
@MainActor
final class ModelCatalogRefresher {
    static let staleAfter: TimeInterval = 24 * 60 * 60

    private let keyStore: AIKeyStore
    private var running = false

    init(secretStore: SecretStore) {
        self.keyStore = AIKeyStore(secretStore: secretStore)
    }

    static func due(keyed: [AIProvider], now: Date,
                    lastRefreshed: (AIProvider) -> Date?) -> [AIProvider] {
        keyed.filter { provider in
            guard let stamp = lastRefreshed(provider) else { return true }
            return now.timeIntervalSince(stamp) > staleAfter
        }
    }

    func refreshStaleCatalogs() {
        guard !running else { return }
        let keyed = AIProvider.allCases.filter {
            ((try? keyStore.key(for: $0)) ?? nil)?.isEmpty == false
        }
        let due = Self.due(keyed: keyed, now: .now,
                           lastRefreshed: ModelCatalog.lastRefreshed(for:))
        guard !due.isEmpty else { return }
        running = true
        Task {
            for provider in due {
                let key = (try? keyStore.key(for: provider)) ?? nil
                if let fresh = try? await ModelCatalog.fetchModels(provider: provider, apiKey: key) {
                    ModelCatalog.storeModels(fresh, for: provider)
                }
            }
            running = false
        }
    }
}
