# AI Agent & Dynamic Model Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Hugging Face as a provider, keep model lists fresh via low-frequency background refresh with a last-known-good cache, and turn the AI chat into a tool-calling agent (run commands over SSH, read/write files over SFTP, app actions) with a configurable approval policy.

**Architecture:** Everything hangs off the existing pure-function AI layer: `RequestEncoder`/`StreamDecoder` gain tool-call support for the two wire formats (Anthropic Messages, OpenAI Chat Completions — OpenRouter and the HF router are OpenAI-compatible). A hand-rolled `AgentLoop` drives stream → approve → execute → append-result → repeat. Tool execution is behind a protocol so the loop tests without SSH, mirroring the `SecretStore` pattern.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Citadel (SSH/SFTP), Swift Testing (`@Test`/`#expect`), xcodeproj with filesystem-synchronized groups (new files under `pockterm/` or `pocktermTests/` are picked up automatically).

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-06-ai-agent-and-model-catalog-design.md`.
- Only `.openai` sends `max_completion_tokens`; `.openRouter` and `.huggingFace` send `max_tokens`; `.anthropic` sends `max_tokens`.
- Model-list cache is only replaced by a successful **non-empty** fetch; never cleared on failure.
- Agent hard cap: 20 iterations per user turn.
- Default approval mode: confirm everything. Unknown commands classify as `mutating`.
- Test command (from project memory — `xcodebuild test` can hang on teardown after tests finish; always redirect to a file, background it if slow, and read results from the log):

  ```bash
  xcodebuild test -project pockterm.xcodeproj -scheme pockterm \
    -destination 'platform=iOS Simulator,name=iPhone 17' \
    -only-testing:pocktermTests > /tmp/pockterm-tests.log 2>&1
  grep -E "✘|✔" /tmp/pockterm-tests.log   # per-test results
  ```

  `-only-testing:pocktermTests/<freeFunctionName>` does NOT match Swift Testing free functions — run the whole `pocktermTests` bundle.

---

# Part 1 — Providers & dynamic model lists

### Task 1: Hugging Face provider

**Files:**
- Modify: `pockterm/AI/AIProvider.swift`
- Modify: `pockterm/AI/RequestEncoder.swift` (switch cases)
- Modify: `pockterm/AI/StreamDecoder.swift` (switch case)
- Modify: `pockterm/AI/ModelCatalog.swift` (auth switch)
- Test: `pocktermTests/RequestEncoderTests.swift`

**Interfaces:**
- Produces: `AIProvider.huggingFace` case usable everywhere `AIProvider` is.

- [ ] **Step 1: Write the failing tests** — append to `pocktermTests/RequestEncoderTests.swift`:

```swift
@Test func huggingFaceUsesOpenAIWireFormatWithMaxTokens() {
    let body = RequestEncoder.body(for: sample, provider: .huggingFace)
    #expect(body["max_tokens"] as? Int == 100)
    #expect(body["max_completion_tokens"] == nil)
    let messages = body["messages"] as? [[String: String]]
    #expect(messages?.first?["role"] == "system")
    #expect(RequestEncoder.headers(for: .huggingFace, apiKey: "K")["Authorization"] == "Bearer K")
}
```

- [ ] **Step 2: Run tests, verify the new one fails to compile** (no `.huggingFace` case). Expected: build error `type 'AIProvider' has no member 'huggingFace'`.

- [ ] **Step 3: Add the case.** In `AIProvider.swift` add `case huggingFace` after `case openRouter`, and extend every property:

```swift
// displayName
case .huggingFace: return "Hugging Face"
// defaultModel
case .huggingFace: return "openai/gpt-oss-120b"
// baseURL
case .huggingFace: return URL(string: "https://router.huggingface.co/v1/chat/completions")!
// modelsURL
case .huggingFace: return URL(string: "https://router.huggingface.co/v1/models")!
```

The compiler now flags every non-exhaustive switch. Fix each by grouping `.huggingFace` with the OpenAI-format cases:
- `RequestEncoder.body`: `case .openai, .openRouter, .huggingFace:` (the existing `tokenField = provider == .openai ? "max_completion_tokens" : "max_tokens"` line already does the right thing for HF).
- `RequestEncoder.headers`: `case .openRouter` keeps its referer lines; add `case .huggingFace: headers["Authorization"] = "Bearer \(apiKey)"`.
- `StreamDecoder.text`: `case .openai, .openRouter, .huggingFace:`.
- `ModelCatalog.fetchModels` auth switch: `case .openai, .openRouter, .huggingFace:` (Bearer).

- [ ] **Step 4: Run tests, verify all pass.**
- [ ] **Step 5: Commit** — `git add -A && git commit -m "Add Hugging Face (Inference Providers router) as an AI provider"` (+ trailer).

---

### Task 2: Text-first model filtering

**Files:**
- Modify: `pockterm/AI/ModelCatalog.swift` (`parseModels`)
- Test: `pocktermTests/ModelCatalogTests.swift` (create if absent; check first — model-parsing tests may live in an existing file, extend that instead)

**Interfaces:**
- Produces: `ModelCatalog.parseModels(_ data: Data, provider: AIProvider) -> [String]` (signature gains `provider`; update the call in `fetchModels` to `parseModels(data, provider: provider)`).

- [ ] **Step 1: Write failing tests:**

```swift
import Foundation
import Testing
@testable import pockterm

@Test func openRouterFilterKeepsTextOutputModels() {
    let json = """
    {"data":[
      {"id":"a/text","architecture":{"modality":"text->text"}},
      {"id":"b/vision","architecture":{"modality":"text+image->text"}},
      {"id":"c/image-gen","architecture":{"modality":"text->image"}},
      {"id":"d/no-arch"}
    ]}
    """.data(using: .utf8)!
    #expect(ModelCatalog.parseModels(json, provider: .openRouter)
            == ["a/text", "b/vision", "d/no-arch"])
}

@Test func openAIFilterDropsNonChatFamilies() {
    let json = """
    {"data":[{"id":"gpt-5"},{"id":"whisper-1"},{"id":"tts-1"},{"id":"dall-e-3"},
             {"id":"text-embedding-3-small"},{"id":"omni-moderation-latest"},
             {"id":"gpt-4o-realtime-preview"},{"id":"gpt-4o"}]}
    """.data(using: .utf8)!
    #expect(ModelCatalog.parseModels(json, provider: .openai) == ["gpt-4o", "gpt-5"])
}

@Test func anthropicAndHFPassThrough() {
    let json = #"{"data":[{"id":"m2"},{"id":"m1"}]}"#.data(using: .utf8)!
    #expect(ModelCatalog.parseModels(json, provider: .anthropic) == ["m1", "m2"])
    #expect(ModelCatalog.parseModels(json, provider: .huggingFace) == ["m1", "m2"])
}
```

- [ ] **Step 2: Run, verify failure** (compile error: extra argument `provider`).
- [ ] **Step 3: Implement** — replace `parseModels`:

```swift
/// All four providers return `{"data": [{"id": "..."}]}`. Text-first policy:
/// OpenRouter is filtered by declared output modality, OpenAI by id family
/// (its list mixes audio/image/embedding models); Anthropic and the HF router
/// already list only chat models.
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
```

Update the call site in `fetchModels`: `return parseModels(data, provider: provider)`. Update any existing `parseModels` test to pass a provider (use `.anthropic` for plain pass-through expectations).

- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Commit** — `"Filter model lists to text-first models"` (+ trailer).

---

### Task 3: Last-known-good hardening + refresh timestamps + seed defaults

**Files:**
- Modify: `pockterm/AI/ModelCatalog.swift`
- Test: `pocktermTests/ModelCatalogTests.swift`

**Interfaces:**
- Produces: `ModelCatalog.lastRefreshed(for: AIProvider) -> Date?`; `storeModels` records the timestamp and ignores empty lists; `ModelCatalog.init` seeds `visibleModels` with `[provider.defaultModel]` when the cache is empty.

- [ ] **Step 1: Failing tests:**

```swift
@Test func storeIgnoresEmptyListAndStampsTime() {
    let provider = AIProvider.anthropic
    UserDefaults.standard.removeObject(forKey: "modelCatalog.\(provider.rawValue)")
    UserDefaults.standard.removeObject(forKey: "modelCatalog.lastRefreshed.\(provider.rawValue)")
    ModelCatalog.storeModels(["m1"], for: provider)
    #expect(ModelCatalog.cachedModels(for: provider) == ["m1"])
    #expect(ModelCatalog.lastRefreshed(for: provider) != nil)
    ModelCatalog.storeModels([], for: provider)          // failure-shaped result
    #expect(ModelCatalog.cachedModels(for: provider) == ["m1"])  // last known good kept
}

@Test @MainActor func emptyCacheSeedsDefaultModel() {
    UserDefaults.standard.removeObject(forKey: "modelCatalog.huggingFace")
    let catalog = ModelCatalog(provider: .huggingFace, apiKey: nil)
    #expect(catalog.visibleModels == [AIProvider.huggingFace.defaultModel])
}
```

- [ ] **Step 2: Run, verify failure** (`lastRefreshed` undefined).
- [ ] **Step 3: Implement.** In `ModelCatalog`:

```swift
private static func stampKey(for provider: AIProvider) -> String {
    "modelCatalog.lastRefreshed.\(provider.rawValue)"
}

static func lastRefreshed(for provider: AIProvider) -> Date? {
    UserDefaults.standard.object(forKey: stampKey(for: provider)) as? Date
}

static func storeModels(_ models: [String], for provider: AIProvider) {
    guard !models.isEmpty else { return }   // never clobber last-known-good
    UserDefaults.standard.set(models, forKey: cacheKey(for: provider))
    UserDefaults.standard.set(Date.now, forKey: stampKey(for: provider))
}
```

In `init`, seed so the picker is never empty:

```swift
let cached = Self.cachedModels(for: provider)
self.visibleModels = cached.isEmpty ? [provider.defaultModel] : cached
```

And in `startRefresh`, direct-replace over a seed: track `private let seeded: Bool` set in init (`seeded = cached.isEmpty`), and change the replace condition to `if ContinuousClock.now - started < .seconds(1) || seeded || visibleModels.isEmpty`.

- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Commit** — `"Harden model cache: non-empty writes only, timestamps, seeded defaults"` (+ trailer).

---

### Task 4: Foreground background-refresh (24 h)

**Files:**
- Create: `pockterm/AI/ModelCatalogRefresher.swift`
- Modify: `pockterm/pocktermApp.swift`, `pockterm/App/AppContainer.swift`
- Test: `pocktermTests/ModelCatalogRefresherTests.swift`

**Interfaces:**
- Consumes: `AIKeyStore(secretStore:)`, `ModelCatalog.fetchModels/storeModels/lastRefreshed`.
- Produces: `ModelCatalogRefresher(secretStore:)` with `func refreshStaleCatalogs()`; pure helper `static func due(keyed: [AIProvider], now: Date, lastRefreshed: (AIProvider) -> Date?) -> [AIProvider]`.

- [ ] **Step 1: Failing test:**

```swift
import Foundation
import Testing
@testable import pockterm

@Test func refreshIsDueOnlyPastStaleWindow() {
    let now = Date.now
    let stamps: [AIProvider: Date] = [.anthropic: now.addingTimeInterval(-25 * 3600),
                                      .openai: now.addingTimeInterval(-1 * 3600)]
    let due = ModelCatalogRefresher.due(keyed: [.anthropic, .openai, .huggingFace],
                                        now: now, lastRefreshed: { stamps[$0] })
    #expect(due == [.anthropic, .huggingFace])  // stale + never-fetched; fresh skipped
}
```

- [ ] **Step 2: Run, verify failure** (type undefined).
- [ ] **Step 3: Implement** `pockterm/AI/ModelCatalogRefresher.swift`:

```swift
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
```

`AppContainer` gains a property (initialized after `secretStore`):

```swift
let modelRefresher: ModelCatalogRefresher
// in init, after secretStore assignment:
modelRefresher = ModelCatalogRefresher(secretStore: store)
```

`pocktermApp` triggers it on activation:

```swift
@main
struct pocktermApp: App {
    @State private var container = AppContainer()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootTabView(secretStore: container.secretStore, sessions: container.sessions,
                        forwards: container.forwards)
                .modelContainer(container.modelContainer)
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { container.modelRefresher.refreshStaleCatalogs() }
                }
        }
    }
}
```

- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Commit** — `"Refresh model lists in the background on foreground, at most daily"` (+ trailer).

---

# Part 2 — The agent

### Task 5: Tool types + message model

**Files:**
- Create: `pockterm/AI/ToolSpec.swift`
- Modify: `pockterm/AI/ChatRequest.swift`
- Test: `pocktermTests/ToolSpecTests.swift`

**Interfaces:**
- Produces:
  - `struct ToolCall: Equatable, Sendable { let id: String; let name: String; let argumentsJSON: String; func arguments() -> [String: Any] }`
  - `struct ToolSpec { let name: String; let description: String; let parameters: [String: Any] }`
  - `ChatMessage` gains `case tool` role, `var toolCalls: [ToolCall] = []`, `var toolCallID: String? = nil`.
  - `ChatRequest` gains `var tools: [ToolSpec] = []`.

- [ ] **Step 1: Failing test:**

```swift
import Testing
@testable import pockterm

@Test func toolCallParsesItsArgumentsJSON() {
    let call = ToolCall(id: "1", name: "run_command",
                        argumentsJSON: #"{"command":"ls -la"}"#)
    #expect(call.arguments()["command"] as? String == "ls -la")
    #expect(ToolCall(id: "2", name: "x", argumentsJSON: "not json").arguments().isEmpty)
}
```

- [ ] **Step 2: Run, verify failure.**
- [ ] **Step 3: Implement** `pockterm/AI/ToolSpec.swift`:

```swift
import Foundation

/// A tool the agent may call: name, human description, JSON-schema parameters.
struct ToolSpec {
    let name: String
    let description: String
    let parameters: [String: Any]
}

/// One tool invocation requested by the model.
struct ToolCall: Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    /// Raw JSON arguments as streamed by the provider.
    let argumentsJSON: String

    func arguments() -> [String: Any] {
        guard let data = argumentsJSON.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return json
    }
}
```

In `ChatRequest.swift`, extend the message and request:

```swift
struct ChatMessage: Equatable {
    enum Role: String { case system, user, assistant, tool }
    let role: Role
    let text: String
    /// Tool invocations attached to an assistant turn.
    var toolCalls: [ToolCall] = []
    /// For role .tool: which call this message answers.
    var toolCallID: String? = nil
}
```

and `var tools: [ToolSpec] = []` on `ChatRequest`. (Existing two-argument `ChatMessage(role:text:)` call sites keep compiling — the new members have defaults.)

- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Commit** — `"Add tool-call types to the chat model"` (+ trailer).

---

### Task 6: Encode tools + tool turns for both wire formats

**Files:**
- Modify: `pockterm/AI/RequestEncoder.swift`
- Test: `pocktermTests/RequestEncoderTests.swift`

**Interfaces:**
- Consumes: Task 5's types.
- Produces: `RequestEncoder.body` emits `tools`, assistant `tool_calls`/`tool_use`, and tool-result turns per provider.

- [ ] **Step 1: Failing tests:**

```swift
private let toolSample: ChatRequest = {
    var request = ChatRequest(
        model: "M", system: nil,
        messages: [
            ChatMessage(role: .user, text: "list files"),
            ChatMessage(role: .assistant, text: "",
                        toolCalls: [ToolCall(id: "c1", name: "run_command",
                                             argumentsJSON: #"{"command":"ls"}"#)]),
            ChatMessage(role: .tool, text: "file.txt", toolCallID: "c1"),
        ])
    request.tools = [ToolSpec(name: "run_command", description: "Run a shell command",
                              parameters: ["type": "object",
                                           "properties": ["command": ["type": "string"]],
                                           "required": ["command"]])]
    return request
}()

@Test func openAIEncodesToolsAndToolTurns() {
    let body = RequestEncoder.body(for: toolSample, provider: .openai)
    let tools = body["tools"] as? [[String: Any]]
    #expect(tools?.first?["type"] as? String == "function")
    let function = tools?.first?["function"] as? [String: Any]
    #expect(function?["name"] as? String == "run_command")

    let messages = body["messages"] as? [[String: Any]]
    let assistant = messages?[1]
    let calls = assistant?["tool_calls"] as? [[String: Any]]
    #expect(calls?.first?["id"] as? String == "c1")
    #expect((calls?.first?["function"] as? [String: Any])?["arguments"] as? String
            == #"{"command":"ls"}"#)
    let toolMsg = messages?[2]
    #expect(toolMsg?["role"] as? String == "tool")
    #expect(toolMsg?["tool_call_id"] as? String == "c1")
    #expect(toolMsg?["content"] as? String == "file.txt")
}

@Test func anthropicEncodesToolsAndToolTurns() {
    let body = RequestEncoder.body(for: toolSample, provider: .anthropic)
    let tools = body["tools"] as? [[String: Any]]
    #expect(tools?.first?["name"] as? String == "run_command")
    #expect(tools?.first?["input_schema"] != nil)

    let messages = body["messages"] as? [[String: Any]]
    let assistantBlocks = messages?[1]["content"] as? [[String: Any]]
    let toolUse = assistantBlocks?.first { $0["type"] as? String == "tool_use" }
    #expect(toolUse?["id"] as? String == "c1")
    #expect((toolUse?["input"] as? [String: Any])?["command"] as? String == "ls")

    let resultMsg = messages?[2]
    #expect(resultMsg?["role"] as? String == "user")
    let resultBlocks = resultMsg?["content"] as? [[String: Any]]
    #expect(resultBlocks?.first?["type"] as? String == "tool_result")
    #expect(resultBlocks?.first?["tool_use_id"] as? String == "c1")
    #expect(resultBlocks?.first?["content"] as? String == "file.txt")
}
```

- [ ] **Step 2: Run, verify failures** (no `tools` key; messages encoded as plain strings).
- [ ] **Step 3: Implement.** Rewrite `RequestEncoder.body` to build messages per provider (replacing the shared `turns` map):

```swift
static func body(for request: ChatRequest, provider: AIProvider) -> [String: Any] {
    switch provider {
    case .anthropic:
        var body: [String: Any] = [
            "model": request.model,
            "max_tokens": request.maxTokens,
            "stream": true,
            "messages": anthropicMessages(request.messages),
        ]
        if let system = request.system { body["system"] = system }
        if !request.tools.isEmpty {
            body["tools"] = request.tools.map {
                ["name": $0.name, "description": $0.description, "input_schema": $0.parameters]
            }
        }
        return body
    case .openai, .openRouter, .huggingFace:
        var messages: [[String: Any]] = []
        if let system = request.system {
            messages.append(["role": "system", "content": system])
        }
        messages += openAIMessages(request.messages)
        let tokenField = provider == .openai ? "max_completion_tokens" : "max_tokens"
        var body: [String: Any] = [
            "model": request.model,
            tokenField: request.maxTokens,
            "stream": true,
            "messages": messages,
        ]
        if !request.tools.isEmpty {
            body["tools"] = request.tools.map {
                ["type": "function",
                 "function": ["name": $0.name, "description": $0.description,
                              "parameters": $0.parameters]]
            }
        }
        return body
    }
}

/// OpenAI Chat Completions turns: assistant tool calls ride a `tool_calls`
/// array; results are role-"tool" messages keyed by `tool_call_id`.
private static func openAIMessages(_ messages: [ChatMessage]) -> [[String: Any]] {
    messages.map { message in
        switch message.role {
        case .tool:
            return ["role": "tool", "tool_call_id": message.toolCallID ?? "",
                    "content": message.text]
        case .assistant where !message.toolCalls.isEmpty:
            var entry: [String: Any] = ["role": "assistant"]
            entry["content"] = message.text.isEmpty ? nil : message.text
            entry["tool_calls"] = message.toolCalls.map {
                ["id": $0.id, "type": "function",
                 "function": ["name": $0.name, "arguments": $0.argumentsJSON]]
            }
            return entry
        default:
            return ["role": message.role.rawValue, "content": message.text]
        }
    }
}

/// Anthropic Messages turns: assistant tool calls are `tool_use` content
/// blocks; results are `tool_result` blocks inside a user turn.
private static func anthropicMessages(_ messages: [ChatMessage]) -> [[String: Any]] {
    messages.map { message in
        switch message.role {
        case .tool:
            return ["role": "user",
                    "content": [["type": "tool_result",
                                 "tool_use_id": message.toolCallID ?? "",
                                 "content": message.text]]]
        case .assistant where !message.toolCalls.isEmpty:
            var blocks: [[String: Any]] = []
            if !message.text.isEmpty { blocks.append(["type": "text", "text": message.text]) }
            blocks += message.toolCalls.map {
                ["type": "tool_use", "id": $0.id, "name": $0.name, "input": $0.arguments()]
            }
            return ["role": "assistant", "content": blocks]
        default:
            return ["role": message.role.rawValue, "content": message.text]
        }
    }
}
```

Note: existing tests cast messages to `[[String: String]]`; plain turns now encode as `[String: Any]`. Update those casts to `[[String: Any]]` with `as? String` on the values.

- [ ] **Step 4: Run tests (all encoder tests), verify pass.**
- [ ] **Step 5: Commit** — `"Encode tool specs and tool turns for Anthropic and OpenAI formats"` (+ trailer).

---

### Task 7: Decode streamed tool calls; AIClient yields events

**Files:**
- Modify: `pockterm/AI/StreamDecoder.swift` (becomes a stateful accumulator)
- Modify: `pockterm/AI/AIClient.swift` (stream of `AIStreamEvent`)
- Modify: `pockterm/Features/AI/AssistantModel.swift` (consume `.text` events)
- Test: `pocktermTests/StreamDecoderTests.swift` (extend existing decoder tests)

**Interfaces:**
- Produces:
  - `enum AIStreamEvent: Equatable, Sendable { case text(String); case toolCall(ToolCall) }`
  - `final class StreamDecoder { init(provider: AIProvider); func events(from line: String) -> [AIStreamEvent]; func finish() -> [AIStreamEvent] }`
  - `AIClient.stream(...) -> AsyncThrowingStream<AIStreamEvent, Error>`; `validate` unchanged externally.

- [ ] **Step 1: Failing tests:**

```swift
@Test func openAIAssemblesStreamedToolCallFragments() {
    let decoder = StreamDecoder(provider: .openai)
    var events: [AIStreamEvent] = []
    let lines = [
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"c1","function":{"name":"run_command","arguments":""}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"comm"}}]}}]}"#,
        #"data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"and\":\"ls\"}"}}]}}]}"#,
        #"data: {"choices":[{"delta":{},"finish_reason":"tool_calls"}]}"#,
        "data: [DONE]",
    ]
    for line in lines { events += decoder.events(from: line) }
    events += decoder.finish()
    #expect(events == [.toolCall(ToolCall(id: "c1", name: "run_command",
                                          argumentsJSON: #"{"command":"ls"}"#))])
}

@Test func anthropicAssemblesToolUseBlocks() {
    let decoder = StreamDecoder(provider: .anthropic)
    var events: [AIStreamEvent] = []
    let lines = [
        #"data: {"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"c9","name":"read_file"}}"#,
        #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"path\":"}}"#,
        #"data: {"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"\"/etc/hosts\"}"}}"#,
        #"data: {"type":"content_block_stop","index":1}"#,
    ]
    for line in lines { events += decoder.events(from: line) }
    #expect(events == [.toolCall(ToolCall(id: "c9", name: "read_file",
                                          argumentsJSON: #"{"path":"/etc/hosts"}"#))])
}

@Test func textDeltasStillFlowAsEvents() {
    let decoder = StreamDecoder(provider: .openai)
    let line = #"data: {"choices":[{"delta":{"content":"hi"}}]}"#
    #expect(decoder.events(from: line) == [.text("hi")])
}
```

Existing decoder tests calling `decoder.text(from:)` must be rewritten as `events(from:)` expecting `[.text(...)]` / `[]`.

- [ ] **Step 2: Run, verify failure.**
- [ ] **Step 3: Implement.** Replace `StreamDecoder.swift`:

```swift
import Foundation

/// What a streaming chat response yields: text deltas as they arrive, and
/// complete tool calls once all their argument fragments have streamed in.
enum AIStreamEvent: Equatable, Sendable {
    case text(String)
    case toolCall(ToolCall)
}

/// Decodes Server-Sent-Events lines into `AIStreamEvent`s, accumulating
/// streamed tool-call fragments (both providers deliver arguments in chunks).
/// Pure state machine over strings so it unit-tests without networking.
final class StreamDecoder {
    let provider: AIProvider
    private struct Partial { var id = ""; var name = ""; var args = "" }
    private var partials: [Int: Partial] = [:]
    private var flushed = false

    init(provider: AIProvider) { self.provider = provider }

    func events(from line: String) -> [AIStreamEvent] {
        guard line.hasPrefix("data:") else { return [] }
        let payload = line.dropFirst("data:".count).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty, payload != "[DONE]",
              let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }

        switch provider {
        case .anthropic: return anthropicEvents(json)
        case .openai, .openRouter, .huggingFace: return openAIEvents(json)
        }
    }

    /// Flush any tool calls still pending at stream end (OpenAI signals
    /// completion via finish_reason on the last delta, which may race [DONE]).
    func finish() -> [AIStreamEvent] {
        guard !flushed else { return [] }
        flushed = true
        return partials.sorted { $0.key < $1.key }.map {
            .toolCall(ToolCall(id: $0.value.id, name: $0.value.name,
                               argumentsJSON: $0.value.args))
        }
    }

    private func anthropicEvents(_ json: [String: Any]) -> [AIStreamEvent] {
        let index = json["index"] as? Int ?? 0
        switch json["type"] as? String {
        case "content_block_start":
            if let block = json["content_block"] as? [String: Any],
               block["type"] as? String == "tool_use" {
                partials[index] = Partial(id: block["id"] as? String ?? "",
                                          name: block["name"] as? String ?? "")
            }
            return []
        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any] else { return [] }
            if delta["type"] as? String == "text_delta", let text = delta["text"] as? String {
                return [.text(text)]
            }
            if delta["type"] as? String == "input_json_delta",
               let chunk = delta["partial_json"] as? String {
                partials[index]?.args += chunk
            }
            return []
        case "content_block_stop":
            guard let partial = partials.removeValue(forKey: index) else { return [] }
            return [.toolCall(ToolCall(id: partial.id, name: partial.name,
                                       argumentsJSON: partial.args))]
        default:
            return []
        }
    }

    private func openAIEvents(_ json: [String: Any]) -> [AIStreamEvent] {
        guard let choice = (json["choices"] as? [[String: Any]])?.first else { return [] }
        if let delta = choice["delta"] as? [String: Any] {
            if let calls = delta["tool_calls"] as? [[String: Any]] {
                for call in calls {
                    let index = call["index"] as? Int ?? 0
                    var partial = partials[index] ?? Partial()
                    if let id = call["id"] as? String { partial.id = id }
                    if let function = call["function"] as? [String: Any] {
                        if let name = function["name"] as? String { partial.name = name }
                        if let chunk = function["arguments"] as? String { partial.args += chunk }
                    }
                    partials[index] = partial
                }
            }
            if let text = delta["content"] as? String { return [.text(text)] }
        }
        if choice["finish_reason"] as? String == "tool_calls" { return finish() }
        return []
    }
}
```

In `AIClient.stream`, the loop becomes:

```swift
let decoder = StreamDecoder(provider: provider)
for try await line in bytes.lines {
    for event in decoder.events(from: line) { continuation.yield(event) }
}
for event in decoder.finish() { continuation.yield(event) }
continuation.finish()
```

with the return type now `AsyncThrowingStream<AIStreamEvent, Error>`. In `AssistantModel.send`, the consumption loop becomes:

```swift
for try await event in await client.stream(request, provider: provider, apiKey: apiKey) {
    if case .text(let delta) = event {
        messages[messages.count - 1].text += delta
    }
}
```

(`validate`'s `for try await _ in … { break }` still compiles unchanged.)

- [ ] **Step 4: Run all tests, verify pass.**
- [ ] **Step 5: Commit** — `"Decode streamed tool calls into events"` (+ trailer).

---

### Task 8: Command risk classifier

**Files:**
- Create: `pockterm/AI/RiskClassifier.swift`
- Test: `pocktermTests/RiskClassifierTests.swift`

**Interfaces:**
- Produces: `enum CommandRisk { case readOnly, mutating }`, `enum RiskClassifier { static func classify(_ command: String) -> CommandRisk }`.

- [ ] **Step 1: Failing table-driven test:**

```swift
import Testing
@testable import pockterm

@Test(arguments: [
    ("ls -la /var/log", CommandRisk.readOnly),
    ("cat /etc/nginx/nginx.conf", .readOnly),
    ("grep -r error /var/log | head -20", .readOnly),
    ("git status && git log --oneline -5", .readOnly),
    ("df -h; uptime", .readOnly),
    ("rm -rf build", CommandRisk.mutating),
    ("sudo systemctl restart nginx", .mutating),
    ("echo hi > /tmp/x", .mutating),          // redirection writes
    ("cat a.txt >> b.txt", .mutating),
    ("ls && rm x", .mutating),                 // any risky segment taints all
    ("frobnicate --all", .mutating),           // unknown ⇒ risky
    ("find . -name '*.log' -delete", .mutating),
])
func classifiesCommands(_ command: String, _ expected: CommandRisk) {
    #expect(RiskClassifier.classify(command) == expected)
}
```

- [ ] **Step 2: Run, verify failure.**
- [ ] **Step 3: Implement** `pockterm/AI/RiskClassifier.swift`:

```swift
import Foundation

enum CommandRisk: Equatable { case readOnly, mutating }

/// Conservative shell-command risk heuristic for the agent's
/// "confirm risky only" mode. Read-only requires every pipeline segment to
/// start with an allowlisted binary and the whole command to be free of
/// redirection and sudo. Anything unknown is mutating.
enum RiskClassifier {
    private static let readOnlyBinaries: Set<String> = [
        "ls", "cat", "head", "tail", "less", "grep", "egrep", "fgrep", "rg",
        "find", "ps", "top", "df", "du", "free", "uname", "whoami", "id",
        "pwd", "echo", "printf", "stat", "file", "wc", "which", "whereis",
        "uptime", "date", "env", "printenv", "hostname", "dig", "nslookup",
        "ping", "netstat", "ss", "journalctl", "dmesg", "history", "man",
        "sort", "uniq", "cut", "awk", "sed", "tr", "column", "diff", "git",
    ]
    /// git subcommands that write; everything else on the allowlist is
    /// treated as read-only (status, log, diff, show, branch listing…).
    private static let mutatingGitSubcommands: Set<String> = [
        "push", "commit", "merge", "rebase", "reset", "checkout", "switch",
        "restore", "clean", "stash", "cherry-pick", "revert", "am", "apply",
        "pull", "fetch", "clone", "init", "add", "rm", "mv", "tag", "remote",
    ]

    static func classify(_ command: String) -> CommandRisk {
        if command.contains(">") || command.contains("sudo") { return .mutating }
        // Split into pipeline/sequence segments; every one must be read-only.
        let segments = command
            .components(separatedBy: CharacterSet(charactersIn: ";|&\n"))
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else { return .mutating }
        for segment in segments {
            let words = segment.split(separator: " ").map(String.init)
            guard let binary = words.first,
                  readOnlyBinaries.contains(binary) else { return .mutating }
            if binary == "git", let sub = words.dropFirst().first(where: { !$0.hasPrefix("-") }),
               mutatingGitSubcommands.contains(sub) { return .mutating }
            if binary == "find", words.contains(where: { $0 == "-delete" || $0 == "-exec" }) {
                return .mutating
            }
            if binary == "sed", words.contains(where: { $0.hasPrefix("-i") }) {
                return .mutating
            }
        }
        return .readOnly
    }
}
```

- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Commit** — `"Add conservative command risk classifier"` (+ trailer).

---

### Task 9: Approval setting

**Files:**
- Modify: `pockterm/Model/AISettings.swift`
- Modify: `pockterm/Features/AI/AISettingsView.swift`
- Test: `pocktermTests/` — extend the existing AISettings persistence test file (`aiSettingsPersists` lives there; keep the new test beside it).

**Interfaces:**
- Produces: `enum AgentApproval: String, CaseIterable, Identifiable { case always, risky, never }` and `AISettings.agentApproval` (stored `agentApprovalRaw`, defaulting to `.always`).

- [ ] **Step 1: Failing test:**

```swift
@Test @MainActor func agentApprovalDefaultsToAlwaysAndPersists() throws {
    let container = try ModelContainer(
        for: AISettings.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let settings = AISettings.single(in: container.mainContext)
    #expect(settings.agentApproval == .always)
    settings.agentApproval = .risky
    #expect(AISettings.single(in: container.mainContext).agentApproval == .risky)
}
```

(Mirror however the existing `aiSettingsPersists` test constructs its in-memory container.)

- [ ] **Step 2: Run, verify failure.**
- [ ] **Step 3: Implement.** In `AISettings.swift`:

```swift
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
```

and on the model (stored default keeps SwiftData's lightweight migration happy):

```swift
var agentApprovalRaw: String = AgentApproval.always.rawValue

var agentApproval: AgentApproval {
    get { AgentApproval(rawValue: agentApprovalRaw) ?? .always }
    set { agentApprovalRaw = newValue.rawValue }
}
```

In `AISettingsView`, add a section below the model picker (adapt to the view's existing Form style):

```swift
Section("Agent") {
    Picker("Approval", selection: approvalBinding) {
        ForEach(AgentApproval.allCases) { Text($0.label).tag($0) }
    }
    Text("Controls whether the assistant asks before running commands or editing files on your server.")
        .font(.footnote).foregroundStyle(.secondary)
}
```

with `private var approvalBinding: Binding<AgentApproval> { Binding(get: { settings.agentApproval }, set: { settings.agentApproval = $0; try? modelContext.save() }) }`.

- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Commit** — `"Add agent approval setting (confirm all / risky / auto-run)"` (+ trailer).

---

### Task 10: SSH exec + the agent's tools

**Files:**
- Modify: `pockterm/SSH/SSHEngine.swift` (exec channel)
- Create: `pockterm/AI/AgentTools.swift` (specs + executor protocol)
- Create: `pockterm/Features/AI/SessionToolExecutor.swift` (live implementation)
- Modify: `pockterm/Features/Terminal/TerminalSession.swift`, `pockterm/Features/Terminal/SessionManager.swift` (back-reference for `open_session`)
- Test: `pocktermTests/AgentToolsTests.swift`

**Interfaces:**
- Consumes: `SFTPService`, `HostConnection.credentials(for:secretStore:)`, `session.decideHostKey`.
- Produces:
  - `SSHEngine.exec(_ command: String, maxOutputBytes: Int) async throws -> String`
  - `protocol AgentToolExecuting { func execute(_ call: ToolCall) async -> String }`
  - `enum AgentTools { static let specs: [ToolSpec]; static func isMutating(_ call: ToolCall) -> Bool }`
  - `SessionToolExecutor(session:modelContext:)` conforming to `AgentToolExecuting`.
  - `TerminalSession.sessionManager: SessionManager?` (weak), set in `SessionManager.open`.

- [ ] **Step 1: Failing tests** (specs shape + risk routing — the live executor is exercised in Task 12's device run, not unit-tested):

```swift
import Testing
@testable import pockterm

@Test func toolSpecsCoverTheAgentSurface() {
    let names = AgentTools.specs.map(\.name).sorted()
    #expect(names == ["list_files", "open_session", "read_file",
                      "run_command", "save_snippet", "write_file"])
    for spec in AgentTools.specs {
        #expect(spec.parameters["type"] as? String == "object")
        #expect(!spec.description.isEmpty)
    }
}

@Test func mutationRoutingMatchesToolAndCommand() {
    func call(_ name: String, _ json: String) -> ToolCall {
        ToolCall(id: "t", name: name, argumentsJSON: json)
    }
    #expect(AgentTools.isMutating(call("read_file", #"{"path":"/a"}"#)) == false)
    #expect(AgentTools.isMutating(call("list_files", #"{"path":"/a"}"#)) == false)
    #expect(AgentTools.isMutating(call("write_file", #"{"path":"/a","content":"x"}"#)) == true)
    #expect(AgentTools.isMutating(call("open_session", #"{"host":"web"}"#)) == true)
    #expect(AgentTools.isMutating(call("save_snippet", #"{"label":"l","command":"c"}"#)) == true)
    #expect(AgentTools.isMutating(call("run_command", #"{"command":"ls"}"#)) == false)
    #expect(AgentTools.isMutating(call("run_command", #"{"command":"rm -rf /tmp/x"}"#)) == true)
    #expect(AgentTools.isMutating(call("unknown_tool", "{}")) == true)
}
```

- [ ] **Step 2: Run, verify failure.**
- [ ] **Step 3: Implement.**

`SSHEngine` gains an exec method (separate channel on the live connection; the PTY shell is untouched). Citadel's `SSHClient.executeCommand(_:maxResponseSize:mergeStreams:inShell:)` collects output; check the version's exact signature in `Package.resolved`'s Citadel checkout if the call doesn't compile, and prefer `mergeStreams: true` so stderr is captured:

```swift
/// Runs one command on a fresh exec channel of the live connection and
/// returns its merged stdout+stderr. The interactive PTY is not disturbed.
func exec(_ command: String, maxOutputBytes: Int = 64 * 1024) async throws -> String {
    guard let client else { throw SSHEngineError.notConnected }
    let buffer = try await client.executeCommand(
        command, maxResponseSize: maxOutputBytes, mergeStreams: true)
    return String(decoding: buffer.readableBytesView, as: UTF8.self)
}
```

`pockterm/AI/AgentTools.swift`:

```swift
import Foundation

/// Executes one approved tool call and returns the text result handed back to
/// the model. Protocol-backed so AgentLoop tests run without SSH.
protocol AgentToolExecuting {
    func execute(_ call: ToolCall) async -> String
}

/// The agent's tool surface: what each tool is called, what the model is told
/// about it, and its JSON-schema arguments.
enum AgentTools {
    static let specs: [ToolSpec] = [
        ToolSpec(name: "run_command",
                 description: "Run a shell command on the connected host and return its combined stdout and stderr. Runs on a separate channel; the user's interactive terminal is not affected.",
                 parameters: schema(["command": ["type": "string", "description": "The shell command to run"]], required: ["command"])),
        ToolSpec(name: "read_file",
                 description: "Read a text file from the connected host over SFTP.",
                 parameters: schema(["path": ["type": "string", "description": "Absolute or home-relative file path"]], required: ["path"])),
        ToolSpec(name: "write_file",
                 description: "Create or overwrite a text file on the connected host over SFTP.",
                 parameters: schema(["path": ["type": "string"],
                                     "content": ["type": "string"]], required: ["path", "content"])),
        ToolSpec(name: "list_files",
                 description: "List a directory on the connected host over SFTP.",
                 parameters: schema(["path": ["type": "string", "description": "Directory path; defaults to home"]], required: [])),
        ToolSpec(name: "open_session",
                 description: "Open a new terminal session to one of the user's saved hosts, by its label.",
                 parameters: schema(["host": ["type": "string", "description": "The saved host's label"]], required: ["host"])),
        ToolSpec(name: "save_snippet",
                 description: "Save a reusable command snippet in the app.",
                 parameters: schema(["label": ["type": "string"],
                                     "command": ["type": "string"]], required: ["label", "command"])),
    ]

    /// Risk routing for "confirm risky only": run_command defers to the
    /// command classifier; everything else is static per tool. Unknown tools
    /// are mutating.
    static func isMutating(_ call: ToolCall) -> Bool {
        switch call.name {
        case "read_file", "list_files":
            return false
        case "run_command":
            let command = call.arguments()["command"] as? String ?? ""
            return RiskClassifier.classify(command) == .mutating
        default:
            return true
        }
    }

    private static func schema(_ properties: [String: Any], required: [String]) -> [String: Any] {
        ["type": "object", "properties": properties, "required": required]
    }
}
```

`pockterm/Features/AI/SessionToolExecutor.swift`:

```swift
import Foundation
import SwiftData

/// Live tool executor for one terminal session: commands run on an exec
/// channel of the session's SSH connection; file tools use a lazily opened
/// SFTP connection to the same host (host-key prompts reuse the session's
/// TOFU flow). Every branch returns text for the model — errors included, so
/// the agent can react instead of dying.
@MainActor
final class SessionToolExecutor: AgentToolExecuting {
    private unowned let session: TerminalSession
    private let modelContext: ModelContext
    private var sftp: SFTPService?

    /// Byte budget for text returned to the model from any one tool call.
    static let outputBudget = 16_000

    init(session: TerminalSession, modelContext: ModelContext) {
        self.session = session
        self.modelContext = modelContext
    }

    func execute(_ call: ToolCall) async -> String {
        let args = call.arguments()
        do {
            switch call.name {
            case "run_command":
                guard let command = args["command"] as? String else { return "error: missing 'command'" }
                let output = try await session.engine.exec(command)
                return Self.truncate(output.isEmpty ? "(no output)" : output)
            case "read_file":
                guard let path = args["path"] as? String else { return "error: missing 'path'" }
                let data = try await sftpService().download(path)
                return Self.truncate(String(decoding: data, as: UTF8.self))
            case "write_file":
                guard let path = args["path"] as? String,
                      let content = args["content"] as? String else {
                    return "error: missing 'path' or 'content'"
                }
                try await sftpService().upload(Data(content.utf8), to: path)
                return "wrote \(content.utf8.count) bytes to \(path)"
            case "list_files":
                let path = args["path"] as? String ?? "."
                let files = try await sftpService().list(path)
                return Self.truncate(files.map {
                    "\($0.kind == .directory ? "d" : "-") \($0.size)\t\($0.name)"
                }.joined(separator: "\n"))
            case "open_session":
                guard let label = args["host"] as? String else { return "error: missing 'host'" }
                let hosts = (try? modelContext.fetch(FetchDescriptor<Host>())) ?? []
                guard let host = hosts.first(where: { $0.label == label }) else {
                    return "error: no saved host labeled '\(label)'. Saved hosts: \(hosts.map(\.label).joined(separator: ", "))"
                }
                session.sessionManager?.open(host)
                return "opened a session to \(label)"
            case "save_snippet":
                guard let label = args["label"] as? String,
                      let command = args["command"] as? String else {
                    return "error: missing 'label' or 'command'"
                }
                modelContext.insert(Snippet(label: label, command: command))
                try? modelContext.save()
                return "saved snippet '\(label)'"
            default:
                return "error: unknown tool '\(call.name)'"
            }
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    private func sftpService() async throws -> SFTPService {
        if let sftp { return sftp }
        guard case .success(let creds) = HostConnection.credentials(for: session.host,
                                                                    secretStore: session.secretStore)
        else { throw SSHEngineError.notConnected }
        let service = SFTPService()
        try await service.connect(creds) { [weak session] presented in
            await session?.decideHostKey(presented) ?? false
        }
        sftp = service
        return service
    }

    static func truncate(_ text: String, budget: Int = outputBudget) -> String {
        guard text.utf8.count > budget else { return text }
        return String(text.prefix(budget)) + "\n…[truncated]"
    }
}
```

(Check `HostConnection.credentials` returns `Result` with `.success(SSHCredentials)` — it does, see `TerminalSession.start`. Mirror `RemoteFilePickerView`'s SFTP setup if it differs.)

`TerminalSession` gains `weak var sessionManager: SessionManager?`, and `SessionManager.open` sets `session.sessionManager = self` right after constructing the session.

- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Commit** — `"Add agent tools: SSH exec, SFTP file ops, app actions"` (+ trailer).

---

### Task 11: The agent loop

**Files:**
- Create: `pockterm/AI/AgentLoop.swift`
- Modify: `pockterm/AI/AIClient.swift` (conform to `ChatStreaming`)
- Test: `pocktermTests/AgentLoopTests.swift`

**Interfaces:**
- Consumes: `AIStreamEvent`, `AgentToolExecuting`, `ChatRequest`.
- Produces:

```swift
protocol ChatStreaming: Sendable {
    func stream(_ request: ChatRequest, provider: AIProvider,
                apiKey: String) async -> AsyncThrowingStream<AIStreamEvent, Error>
}

@MainActor final class AgentLoop {
    enum Event {
        case assistantDelta(String)         // streaming text for the visible bubble
        case assistantTurnEnded             // close the current bubble
        case toolPending(ToolCall)          // waiting on approval
        case toolStarted(ToolCall)
        case toolFinished(ToolCall, result: String)
        case toolDenied(ToolCall)
        case hitIterationCap
    }
    static let maxIterations = 20
    init(client: ChatStreaming, executor: AgentToolExecuting)
    func run(request: ChatRequest, provider: AIProvider, apiKey: String,
             approve: @escaping (ToolCall) async -> Bool,
             onEvent: @escaping (Event) -> Void) async throws
}
```

- [ ] **Step 1: Failing tests** with a scripted fake:

```swift
import Testing
@testable import pockterm

/// Yields a scripted list of event-lists, one per stream() call, and records
/// each request it was asked to send.
final class FakeChat: ChatStreaming, @unchecked Sendable {
    var turns: [[AIStreamEvent]]
    var requests: [ChatRequest] = []
    init(turns: [[AIStreamEvent]]) { self.turns = turns }

    func stream(_ request: ChatRequest, provider: AIProvider,
                apiKey: String) async -> AsyncThrowingStream<AIStreamEvent, Error> {
        requests.append(request)
        let turn = turns.isEmpty ? [] : turns.removeFirst()
        return AsyncThrowingStream { continuation in
            for event in turn { continuation.yield(event) }
            continuation.finish()
        }
    }
}

final class FakeExecutor: AgentToolExecuting, @unchecked Sendable {
    var executed: [ToolCall] = []
    func execute(_ call: ToolCall) async -> String {
        executed.append(call)
        return "ok:\(call.name)"
    }
}

private func makeRequest() -> ChatRequest {
    ChatRequest(model: "m", system: nil,
                messages: [ChatMessage(role: .user, text: "do it")])
}

@Test @MainActor func runsToolThenContinuesUntilPlainReply() async throws {
    let call = ToolCall(id: "c1", name: "run_command", argumentsJSON: #"{"command":"ls"}"#)
    let chat = FakeChat(turns: [[.toolCall(call)], [.text("done")]])
    let executor = FakeExecutor()
    let loop = AgentLoop(client: chat, executor: executor)
    var events: [AgentLoop.Event] = []
    try await loop.run(request: makeRequest(), provider: .openai, apiKey: "k",
                       approve: { _ in true }, onEvent: { events.append($0) })
    #expect(executor.executed == [call])
    #expect(chat.requests.count == 2)
    // Second request carries the assistant tool turn + the tool result.
    let followUp = chat.requests[1].messages
    #expect(followUp.contains { $0.role == .assistant && $0.toolCalls == [call] })
    #expect(followUp.contains { $0.role == .tool && $0.toolCallID == "c1" && $0.text == "ok:run_command" })
    #expect(events.contains { if case .assistantDelta("done") = $0 { return true }; return false })
}

@Test @MainActor func denialSendsDeclinedResultAndContinues() async throws {
    let call = ToolCall(id: "c1", name: "write_file", argumentsJSON: "{}")
    let chat = FakeChat(turns: [[.toolCall(call)], [.text("understood")]])
    let executor = FakeExecutor()
    let loop = AgentLoop(client: chat, executor: executor)
    try await loop.run(request: makeRequest(), provider: .openai, apiKey: "k",
                       approve: { _ in false }, onEvent: { _ in })
    #expect(executor.executed.isEmpty)
    #expect(chat.requests[1].messages.contains {
        $0.role == .tool && $0.text.contains("declined")
    })
}

@Test @MainActor func iterationCapStopsRunawayLoop() async throws {
    let call = ToolCall(id: "c", name: "run_command", argumentsJSON: #"{"command":"ls"}"#)
    let chat = FakeChat(turns: Array(repeating: [.toolCall(call)], count: 30))
    let loop = AgentLoop(client: chat, executor: FakeExecutor())
    var capped = false
    try await loop.run(request: makeRequest(), provider: .openai, apiKey: "k",
                       approve: { _ in true },
                       onEvent: { if case .hitIterationCap = $0 { capped = true } })
    #expect(capped)
    #expect(chat.requests.count == AgentLoop.maxIterations)
}
```

- [ ] **Step 2: Run, verify failure.**
- [ ] **Step 3: Implement** `pockterm/AI/AgentLoop.swift`:

```swift
import Foundation

/// Abstraction over AIClient's streaming call so the agent loop can be tested
/// against a scripted fake.
protocol ChatStreaming: Sendable {
    func stream(_ request: ChatRequest, provider: AIProvider,
                apiKey: String) async -> AsyncThrowingStream<AIStreamEvent, Error>
}

extension AIClient: ChatStreaming {}

/// The agent: streams a reply, and while the model keeps requesting tools,
/// gets each call approved, executes it, appends the result, and goes again.
/// Ends on a plain reply, a thrown stream error, or the iteration cap.
@MainActor
final class AgentLoop {
    enum Event {
        case assistantDelta(String)
        case assistantTurnEnded
        case toolPending(ToolCall)
        case toolStarted(ToolCall)
        case toolFinished(ToolCall, result: String)
        case toolDenied(ToolCall)
        case hitIterationCap
    }

    static let maxIterations = 20

    private let client: ChatStreaming
    private let executor: AgentToolExecuting

    init(client: ChatStreaming, executor: AgentToolExecuting) {
        self.client = client
        self.executor = executor
    }

    func run(request: ChatRequest, provider: AIProvider, apiKey: String,
             approve: @escaping (ToolCall) async -> Bool,
             onEvent: @escaping (Event) -> Void) async throws {
        var messages = request.messages

        for _ in 0..<Self.maxIterations {
            var current = request
            current.messages = messages

            var streamedText = ""
            var toolCalls: [ToolCall] = []
            for try await event in await client.stream(current, provider: provider, apiKey: apiKey) {
                switch event {
                case .text(let delta):
                    streamedText += delta
                    onEvent(.assistantDelta(delta))
                case .toolCall(let call):
                    toolCalls.append(call)
                }
            }
            onEvent(.assistantTurnEnded)
            messages.append(ChatMessage(role: .assistant, text: streamedText,
                                        toolCalls: toolCalls))
            guard !toolCalls.isEmpty else { return }

            for call in toolCalls {
                onEvent(.toolPending(call))
                if await approve(call) {
                    onEvent(.toolStarted(call))
                    let result = await executor.execute(call)
                    onEvent(.toolFinished(call, result: result))
                    messages.append(ChatMessage(role: .tool, text: result, toolCallID: call.id))
                } else {
                    onEvent(.toolDenied(call))
                    messages.append(ChatMessage(role: .tool,
                                                text: "The user declined this tool call.",
                                                toolCallID: call.id))
                }
                try Task.checkCancellation()
            }
        }
        onEvent(.hitIterationCap)
    }
}
```

Note `ChatRequest.messages` must become `var` (it is currently `let`) — change it in `ChatRequest.swift`.

- [ ] **Step 4: Run tests, verify pass.**
- [ ] **Step 5: Commit** — `"Add hand-rolled agent loop with approval and iteration cap"` (+ trailer).

---

### Task 12: Wire the agent into AssistantModel + chat UI

**Files:**
- Modify: `pockterm/Features/AI/AssistantModel.swift`
- Modify: `pockterm/Features/AI/AssistantView.swift`
- Test: existing suite must stay green (this task is UI/orchestration; its verification is Task 13's end-to-end run).

**Interfaces:**
- Consumes: `AgentLoop`, `SessionToolExecutor`, `AgentTools`, `AISettings.agentApproval`.
- Produces: transcript entries for tool activity and an approval card.

- [ ] **Step 1: Extend the transcript model.** In `AssistantModel.swift`:

```swift
struct AssistantMessage: Identifiable {
    enum Role { case user, assistant, tool }
    let id = UUID()
    let role: Role
    var text: String
    /// For role .tool: which tool ran and how it ended.
    var toolName: String?
    var toolDetail: String?      // e.g. the command or path
    var toolResult: String?
    var denied = false
    // commands: [String] — unchanged, still assistant-only
}

/// A tool call waiting for the user's Run/Deny, same continuation pattern as
/// PendingHostKey.
struct PendingToolApproval: Identifiable {
    let id = UUID()
    let call: ToolCall
    let resume: (Bool) -> Void
}
```

- [ ] **Step 2: Replace the streaming body of `send`** (context assembly and turn-merging stay as they are) — after building `turns`:

```swift
var request = ChatRequest(model: settings.model, system: system, messages: turns)
request.tools = AgentTools.specs

messages.append(AssistantMessage(role: .assistant, text: ""))
isStreaming = true
let approvalMode = settings.agentApproval
let loop = AgentLoop(client: client,
                     executor: SessionToolExecutor(session: session, modelContext: modelContext))
streamTask = Task { [weak self] in
    guard let self else { return }
    do {
        try await loop.run(request: request, provider: provider, apiKey: apiKey,
                           approve: { [weak self] call in
                               await self?.approve(call, mode: approvalMode) ?? false
                           },
                           onEvent: { [weak self] event in self?.handle(event) })
    } catch is CancellationError {
        // User tapped stop; keep whatever streamed so far.
    } catch {
        errorMessage = error.localizedDescription
    }
    if messages.last?.role == .assistant, messages.last?.text.isEmpty == true {
        messages.removeLast()
    }
    isStreaming = false
}
```

with the two new members:

```swift
var pendingApproval: PendingToolApproval?

private func approve(_ call: ToolCall, mode: AgentApproval) async -> Bool {
    switch mode {
    case .never: return true
    case .risky where !AgentTools.isMutating(call): return true
    default:
        return await withCheckedContinuation { continuation in
            pendingApproval = PendingToolApproval(call: call) { decision in
                continuation.resume(returning: decision)
            }
        }
    }
}

func resolveApproval(_ approved: Bool) {
    pendingApproval?.resume(approved)
    pendingApproval = nil
}

private func handle(_ event: AgentLoop.Event) {
    switch event {
    case .assistantDelta(let delta):
        if messages.last?.role != .assistant {
            messages.append(AssistantMessage(role: .assistant, text: ""))
        }
        messages[messages.count - 1].text += delta
    case .assistantTurnEnded:
        if messages.last?.role == .assistant, messages.last?.text.isEmpty == true {
            messages.removeLast()
        }
    case .toolPending:
        break   // the approval card renders from pendingApproval
    case .toolStarted(let call):
        messages.append(AssistantMessage(role: .tool, text: "",
                                         toolName: call.name,
                                         toolDetail: Self.summary(of: call)))
    case .toolFinished(let call, let result):
        if let index = messages.lastIndex(where: { $0.role == .tool && $0.toolName == call.name && $0.toolResult == nil }) {
            messages[index].toolResult = result
        }
    case .toolDenied(let call):
        var entry = AssistantMessage(role: .tool, text: "",
                                     toolName: call.name, toolDetail: Self.summary(of: call))
        entry.denied = true
        messages.append(entry)
    case .hitIterationCap:
        errorMessage = "Stopped after \(AgentLoop.maxIterations) agent steps."
    }
}

/// One-line human summary of a call for the transcript card.
static func summary(of call: ToolCall) -> String {
    let args = call.arguments()
    return args["command"] as? String
        ?? args["path"] as? String
        ?? args["host"] as? String
        ?? args["label"] as? String
        ?? ""
}
```

- [ ] **Step 3: Render in `AssistantView`.** Read the existing message-bubble `ForEach` first and match its styling. Add a card for `role == .tool`:

```swift
// inside the transcript ForEach, alongside the user/assistant bubbles
if message.role == .tool {
    VStack(alignment: .leading, spacing: 4) {
        Label(message.toolName ?? "tool", systemImage: message.denied ? "hand.raised" : "wrench.and.screwdriver")
            .font(.caption.bold())
        if let detail = message.toolDetail, !detail.isEmpty {
            Text(detail).font(.system(.caption, design: .monospaced))
        }
        if message.denied {
            Text("Denied").font(.caption2).foregroundStyle(.red)
        } else if let result = message.toolResult {
            Text(result.prefix(400))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(8)
        } else {
            ProgressView().controlSize(.small)
        }
    }
    .padding(10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
}
```

and, pinned above the input bar, an approval card driven by `model.pendingApproval`:

```swift
if let pending = model.pendingApproval {
    VStack(alignment: .leading, spacing: 8) {
        Label("The assistant wants to run:", systemImage: "exclamationmark.shield")
            .font(.caption.bold())
        Text("\(pending.call.name): \(AssistantModel.summary(of: pending.call))")
            .font(.system(.caption, design: .monospaced))
            .lineLimit(6)
        HStack {
            Button("Deny", role: .destructive) { model.resolveApproval(false) }
            Spacer()
            Button("Run") { model.resolveApproval(true) }
                .buttonStyle(.borderedProminent)
        }
    }
    .padding()
    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
    .padding(.horizontal)
}
```

Also make `stop()` resolve any pending approval as denied first: `func stop() { resolveApproval(false); streamTask?.cancel() }` — but only when one is pending (`if pendingApproval != nil { resolveApproval(false) }`).

- [ ] **Step 4: Build + run the full unit suite, verify green.**
- [ ] **Step 5: Commit** — `"Wire agent loop into assistant chat with approval cards"` (+ trailer).

---

### Task 13: End-to-end verification on the simulator

**Files:** none (verification only)

- [ ] **Step 1: Full test suite** — run the Global Constraints test command; every test passes.
- [ ] **Step 2: Build & install on the booted iPhone 17 simulator** (UDID `B2AD7C4B-3A87-4A5D-9A9D-CF564F8BA7D2`, per project memory — verify with `xcrun simctl list devices booted`):

```bash
xcodebuild -project pockterm.xcodeproj -scheme pockterm -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 17' build > /tmp/pockterm-build.log 2>&1
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/pockterm-*/Build/Products/Debug-iphonesimulator/pockterm.app | head -1)
xcrun simctl install B2AD7C4B-3A87-4A5D-9A9D-CF564F8BA7D2 "$APP"
xcrun simctl launch B2AD7C4B-3A87-4A5D-9A9D-CF564F8BA7D2 John-Hancock.pockterm
xcrun simctl io B2AD7C4B-3A87-4A5D-9A9D-CF564F8BA7D2 screenshot /tmp/pockterm-agent.png
```

Pick DerivedData by newest mtime (stale `pockterm-*` dirs exist; an old one contains a template app).

- [ ] **Step 3: Manual smoke checklist** (use the ios-debugger-agent skill to drive the simulator UI):
  - AI Settings shows four providers including Hugging Face and the Agent approval picker.
  - With a real key, Test succeeds against a current OpenAI model (regression check on `max_completion_tokens`).
  - Model picker shows a non-empty list with no key/cache (seeded default).
  - In a connected session, ask the assistant to "list the files in my home directory and read one of them" — expect an approval card, then tool cards with output.
- [ ] **Step 4: Send the screenshot to the user** and report results honestly (any step that couldn't run — e.g. no live SSH host from the simulator, no API key available — is reported as not-verified, not skipped silently).
- [ ] **Step 5: Commit any fixes; final commit** — `"Verify agent end-to-end on simulator"` only if fixes were needed.
