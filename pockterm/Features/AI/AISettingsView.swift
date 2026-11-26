import SwiftUI
import SwiftData

/// Configures the assistant: active provider, model, and a per-provider API
/// key kept in the Keychain.
struct AISettingsView: View {
    let secretStore: SecretStore
    @Environment(\.modelContext) private var modelContext
    @Query private var allSettings: [AISettings]

    var body: some View {
        Group {
            if let settings = allSettings.first {
                AISettingsForm(settings: settings, keyStore: AIKeyStore(secretStore: secretStore))
            } else {
                ProgressView()
            }
        }
        .navigationTitle("AI Assistant")
        .task {
            _ = AISettings.single(in: modelContext)
        }
    }
}

private struct AISettingsForm: View {
    @Bindable var settings: AISettings
    let keyStore: AIKeyStore

    enum TestState: Equatable { case idle, testing, success, failure(String) }
    enum ServerState: Equatable { case idle, checking, found(Int), failure(String) }
    @State private var keyInput = ""
    @FocusState private var keyFieldFocused: Bool
    @FocusState private var addressFieldFocused: Bool
    @State private var addressInput = CustomServer.address
    @State private var serverState: ServerState = .idle
    @State private var hasStoredKey = false
    @State private var testState: TestState = .idle
    @State private var keychainError: String?
    private let client = AIClient()

    var body: some View {
        Form {
            Section("Provider") {
                Picker("Provider", selection: providerBinding) {
                    ForEach(AIProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                NavigationLink {
                    ModelPickerView(settings: settings,
                                    apiKey: (try? keyStore.key(for: settings.activeProvider)) ?? nil)
                } label: {
                    HStack {
                        Text("Model")
                        Spacer()
                        Text(settings.model.isEmpty ? String(localized: "None") : settings.model)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            if settings.activeProvider == .custom {
                serverSection
            }

            Section {
                Picker("Approval", selection: $settings.agentApproval) {
                    ForEach(AgentApproval.allCases) { Text($0.label).tag($0) }
                }
            } header: {
                Text("Agent")
            } footer: {
                Text("Controls whether the assistant asks before running commands or editing files on your server.")
            }

            Section {
                if hasStoredKey {
                    HStack {
                        Label("Key saved in Keychain", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                        Spacer()
                        Button("Remove", role: .destructive) { removeKey() }
                    }
                }
                SecureField(hasStoredKey ? "Replace API key" : "Paste API key", text: $keyInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .focused($keyFieldFocused)
                Button("Save Key") { saveKey() }
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let help = settings.activeProvider.apiKeyHelpURL {
                    Link(destination: help) {
                        Label("Get an API key", systemImage: "arrow.up.right.square")
                    }
                }
                if let keychainError {
                    Text(keychainError).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                if settings.activeProvider.requiresAPIKey {
                    Text("\(settings.activeProvider.displayName) API Key")
                } else {
                    Text("API Key (Optional)")
                }
            } footer: {
                if settings.activeProvider.requiresAPIKey {
                    Text("Keys are stored in the iOS Keychain and sent only to \(settings.activeProvider.displayName).")
                } else {
                    Text("Only needed if your server was set up to ask for one. Kept in the iOS Keychain and sent only to your server.")
                }
            }

            Section {
                Button { test() } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        switch testState {
                        case .idle: EmptyView()
                        case .testing: ProgressView()
                        case .success: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        case .failure: Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                        }
                    }
                }
                .disabled(!canTest || testState == .testing)
                if case .failure(let message) = testState {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            } footer: {
                Text("Sends a one-token request to verify the key and model.")
            }
        }
        .toolbar {
            // Same chip as HostEditorView, so dismissing works identically
            // wherever the app takes typed input.
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button { keyFieldFocused = false; addressFieldFocused = false } label: {
                    Image(systemName: "keyboard.chevron.compact.down")
                }
                .accessibilityLabel("Dismiss Keyboard")
            }
        }
        .onAppear { refreshKeyState() }
    }

    /// Where a self-hosted model server is. Saving it asks the server for its
    /// models straight away, so a wrong address or a server that only listens
    /// on its own machine shows up here rather than in the assistant.
    private var serverSection: some View {
        Section {
            TextField("Server address", text: $addressInput,
                      prompt: Text(verbatim: "http://192.168.1.20:11434"))
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .focused($addressFieldFocused)
                .onSubmit { saveAddress() }
                // The prompt replaces the title on screen, so VoiceOver would
                // read only the example address.
                .accessibilityLabel("Server address")
            Button("Save and Find Models") { saveAddress() }
                .disabled(CustomServer.endpoints(from: addressInput) == nil || serverState == .checking)
            switch serverState {
            case .idle: EmptyView()
            case .checking:
                HStack { ProgressView(); Text("Asking the server for its models…").foregroundStyle(.secondary) }
            case .found(let count):
                Label("Connected. Models found: \(count)", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .failure(let message):
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        } header: {
            Text("Server")
        } footer: {
            Text("Works with Ollama (port 11434), llama.cpp's llama-server (port 8080), LM Studio and other servers with an OpenAI-compatible API. Start the server so other devices can reach it: OLLAMA_HOST=0.0.0.0 for Ollama, --host 0.0.0.0 for llama-server. Away from home, use a VPN such as Tailscale.")
        }
    }

    private var canTest: Bool {
        let provider = settings.activeProvider
        return (hasStoredKey || !provider.requiresAPIKey) && provider.baseURL != nil
            && !settings.model.isEmpty
    }

    private func saveAddress() {
        guard CustomServer.endpoints(from: addressInput) != nil else { return }
        addressFieldFocused = false
        if CustomServer.address != addressInput.trimmingCharacters(in: .whitespacesAndNewlines) {
            ModelCatalog.clearCache(for: .custom)
        }
        CustomServer.address = addressInput
        addressInput = CustomServer.address
        serverState = .checking
        testState = .idle
        let key = (try? keyStore.key(for: .custom)) ?? nil
        Task {
            do {
                let models = try await ModelCatalog.fetchModels(provider: .custom, apiKey: key)
                ModelCatalog.storeModels(models, for: .custom)
                if !models.contains(settings.model), let first = models.first {
                    settings.model = first
                }
                serverState = models.isEmpty
                    ? .failure(String(localized: "The server answered but has no models. Download one first, for example with ollama pull."))
                    : .found(models.count)
            } catch {
                serverState = .failure(error.localizedDescription)
            }
        }
    }

    private var providerBinding: Binding<AIProvider> {
        Binding(get: { settings.activeProvider },
                set: { provider in
                    settings.activeProvider = provider
                    settings.model = provider == .custom
                        ? (ModelCatalog.cachedModels(for: .custom).first ?? "")
                        : provider.defaultModel
                    serverState = .idle
                    keyInput = ""
                    testState = .idle
                    refreshKeyState()
                })
    }

    private func refreshKeyState() {
        hasStoredKey = ((try? keyStore.key(for: settings.activeProvider)) ?? nil)?.isEmpty == false
    }

    private func saveKey() {
        do {
            try keyStore.setKey(keyInput, for: settings.activeProvider)
            keychainError = nil
            keyInput = ""
        } catch {
            keychainError = String(localized: "Couldn't save to the Keychain: \(error.localizedDescription)")
        }
        testState = .idle
        refreshKeyState()
    }

    private func removeKey() {
        try? keyStore.removeKey(for: settings.activeProvider)
        testState = .idle
        refreshKeyState()
    }

    private func test() {
        let key = ((try? keyStore.key(for: settings.activeProvider)) ?? nil) ?? ""
        guard canTest else { return }
        testState = .testing
        let provider = settings.activeProvider
        let model = settings.model
        Task {
            do {
                try await client.validate(provider: provider, model: model, apiKey: key)
                testState = .success
            } catch {
                testState = .failure(error.localizedDescription)
            }
        }
    }
}
