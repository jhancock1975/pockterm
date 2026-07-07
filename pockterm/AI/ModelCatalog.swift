import Foundation

/// Loads the list of model ids a provider offers, with a cache so the picker
/// is instant. On refresh: a response inside one second replaces the visible
/// list directly; a slower one keeps retrying in the background (exponential
/// backoff) and lands in `pendingUpdate` so the list a user is looking at
/// never changes under their finger.
@MainActor
@Observable
final class ModelCatalog {
    let provider: AIProvider
    private let apiKey: String?

    /// What the picker shows. Frozen once shown, except for a fast (<1s)
    /// first response or when there was nothing cached to show at all.
    private(set) var visibleModels: [String]
    /// A newer list that arrived while the user was already looking.
    private(set) var pendingUpdate: [String]?
    private(set) var isRefreshing = false
    private(set) var refreshFailed = false

    private var refreshTask: Task<Void, Never>?
    /// True when there was nothing cached and the list is just the provider's
    /// default model — the first successful fetch then replaces it directly.
    private let seeded: Bool

    init(provider: AIProvider, apiKey: String?) {
        self.provider = provider
        self.apiKey = apiKey
        let cached = Self.cachedModels(for: provider)
        self.seeded = cached.isEmpty
        self.visibleModels = cached.isEmpty ? [provider.defaultModel] : cached
    }

    func startRefresh() {
        guard refreshTask == nil else { return }
        isRefreshing = true
        refreshFailed = false
        let started = ContinuousClock.now
        refreshTask = Task {
            var delay: Duration = .seconds(2)
            for _ in 0..<5 {
                do {
                    let fresh = try await Self.fetchModels(provider: provider, apiKey: apiKey)
                    guard !Task.isCancelled else { return }
                    Self.storeModels(fresh, for: provider)
                    if ContinuousClock.now - started < .seconds(1) || seeded || visibleModels.isEmpty {
                        visibleModels = fresh
                    } else if fresh != visibleModels {
                        pendingUpdate = fresh
                    }
                    isRefreshing = false
                    return
                } catch {
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: delay)
                    delay *= 2
                }
            }
            isRefreshing = false
            refreshFailed = true
        }
    }

    func applyPendingUpdate() {
        if let pendingUpdate { visibleModels = pendingUpdate }
        pendingUpdate = nil
    }

    func cancel() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: Fetch + parse

    static func fetchModels(provider: AIProvider, apiKey: String?) async throws -> [String] {
        var request = URLRequest(url: provider.modelsURL)
        if let apiKey, !apiKey.isEmpty {
            switch provider {
            case .anthropic:
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            case .openai, .openRouter, .huggingFace:
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            }
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AIClientError(status: http.statusCode,
                                detail: String(decoding: data, as: UTF8.self))
        }
        return parseModels(data, provider: provider)
    }

    /// All four providers return `{"data": [{"id": "..."}]}`. Text-first policy:
    /// OpenRouter is filtered by declared output modality, OpenAI by id family
    /// (its list mixes audio/image/embedding models); Anthropic and the HF
    /// router already list only chat models.
    static func parseModels(_ data: Data, provider: AIProvider) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]]
        else { return [] }
        let ids: [String]
        switch provider {
        case .openRouter:
            ids = entries.compactMap { entry in
                guard let id = entry["id"] as? String else { return nil }
                if let arch = entry["architecture"] as? [String: Any],
                   let modality = arch["modality"] as? String,
                   !modality.hasSuffix("->text") { return nil }
                return id
            }
        case .openai:
            let nonChat = ["whisper", "tts", "dall-e", "embedding", "moderation",
                           "realtime", "audio", "image", "transcribe", "davinci", "babbage"]
            ids = entries.compactMap { $0["id"] as? String }
                .filter { id in !nonChat.contains { id.contains($0) } }
        case .anthropic, .huggingFace:
            ids = entries.compactMap { $0["id"] as? String }
        }
        return ids.sorted()
    }

    // MARK: Cache

    private static func cacheKey(for provider: AIProvider) -> String {
        "modelCatalog.\(provider.rawValue)"
    }

    private static func stampKey(for provider: AIProvider) -> String {
        "modelCatalog.lastRefreshed.\(provider.rawValue)"
    }

    static func cachedModels(for provider: AIProvider) -> [String] {
        UserDefaults.standard.stringArray(forKey: cacheKey(for: provider)) ?? []
    }

    static func lastRefreshed(for provider: AIProvider) -> Date? {
        UserDefaults.standard.object(forKey: stampKey(for: provider)) as? Date
    }

    static func storeModels(_ models: [String], for provider: AIProvider) {
        guard !models.isEmpty else { return }   // never clobber last-known-good
        UserDefaults.standard.set(models, forKey: cacheKey(for: provider))
        UserDefaults.standard.set(Date.now, forKey: stampKey(for: provider))
    }
}
