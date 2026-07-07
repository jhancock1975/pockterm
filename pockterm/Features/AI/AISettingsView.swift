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
    @State private var keyInput = ""
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
                        Text(settings.model)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
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
                Button("Save Key") { saveKey() }
                    .disabled(keyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                if let keychainError {
                    Text(keychainError).font(.footnote).foregroundStyle(.red)
                }
            } header: {
                Text("\(settings.activeProvider.displayName) API Key")
            } footer: {
                Text("Keys are stored in the iOS Keychain and sent only to \(settings.activeProvider.displayName).")
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
                .disabled(!hasStoredKey || testState == .testing)
                if case .failure(let message) = testState {
                    Text(message).font(.footnote).foregroundStyle(.red)
                }
            } footer: {
                Text("Sends a one-token request to verify the key and model.")
            }
        }
        .onAppear { refreshKeyState() }
    }

    private var providerBinding: Binding<AIProvider> {
        Binding(get: { settings.activeProvider },
                set: { provider in
                    settings.activeProvider = provider
                    settings.model = provider.defaultModel
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
            keychainError = "Couldn't save to the Keychain: \(error.localizedDescription)"
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
        guard let key = (try? keyStore.key(for: settings.activeProvider)) ?? nil else { return }
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
