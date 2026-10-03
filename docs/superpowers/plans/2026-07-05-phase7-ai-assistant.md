# Phase 7: AI Assistant — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax. When writing the Anthropic request/streaming code, follow the claude-api skill (Swift is unsupported by the SDK → raw HTTPS against `/v1/messages`; default model `claude-opus-4-8`; stream).

**Goal:** An in-app assistant that reads the active terminal's text (and user-attached files) as context and answers/suggests commands, using the user's own API key for OpenAI, Anthropic, or OpenRouter.

**Architecture:** A normalized `ChatRequest` (system + messages + model) is encoded to each provider's HTTP body (pure, TDD) and its streamed SSE is decoded to text deltas (pure, TDD). `AIClient` does the URLSession streaming. Keys live in the Keychain via `SecretStore`. Context (terminal text + attachments, size-capped) is assembled by a pure builder (TDD). SwiftUI provides a Settings screen (keys/provider/model) and a chat surface.

**Tech Stack:** SwiftUI, SwiftData, URLSession (raw HTTPS — no SDK for Swift). No new packages.

## Global Constraints
- iOS 26.5+, Swift 5 mode; app files auto-compile; new TEST files need `ruby scripts/setup_project.rb`.
- Secrets go through `SecretStore` only — never SwiftData/plaintext.

---

### Task 1: Provider model + normalized request types

**Files:** Create `pockterm/AI/AIProvider.swift`, `pockterm/AI/ChatRequest.swift`; Test `pocktermTests/AIProviderTests.swift`

- `enum AIProvider: String, CaseIterable, Codable { case openai, anthropic, openRouter }` with `displayName`, `defaultModel` (anthropic → `claude-opus-4-8`; openai → documented default; openRouter → documented default), `baseURL`, `keychainKeyID` (stable per-provider id for `SecretStore`).
- `struct ChatMessage { enum Role { system, user, assistant }; let role; let text }`
- `struct ChatRequest { let model: String; let system: String?; let messages: [ChatMessage]; let maxTokens: Int }`

- [ ] Test: each provider exposes a non-empty `defaultModel`, a valid `https` `baseURL`, and a unique `keychainKeyID`.
- [ ] Implement; run; commit `"Add AIProvider and ChatRequest models"`.

---

### Task 2: Per-provider request encoding (pure, TDD)

**Files:** Create `pockterm/AI/RequestEncoder.swift`; Test `pocktermTests/RequestEncoderTests.swift`

- `enum RequestEncoder { static func body(for: ChatRequest, provider: AIProvider) -> [String: Any]; static func headers(for: AIProvider, apiKey: String) -> [String: String] }`
  - Anthropic: body `{model, max_tokens, system?, messages:[{role,content}], stream:true}` (system as top-level field; user/assistant only in messages); headers `x-api-key`, `anthropic-version: 2023-06-01`, `content-type`.
  - OpenAI / OpenRouter: body `{model, messages:[{role,content}], stream:true}` with the system prompt as a leading `{role:"system"}` message; headers `Authorization: Bearer <key>`, `content-type`. OpenRouter adds `HTTP-Referer`/`X-Title` (app id).

- [ ] Test: Anthropic body puts `system` top-level and excludes it from `messages`; OpenAI body has a leading system message; both set `stream:true` and the right `model`; headers carry the key in the correct field per provider.
- [ ] Implement; run; commit `"Add per-provider request encoding"`.

---

### Task 3: Streaming SSE decoding (pure, TDD)

**Files:** Create `pockterm/AI/StreamDecoder.swift`; Test `pocktermTests/StreamDecoderTests.swift`

- `struct StreamDecoder { let provider: AIProvider; mutating func consume(line: String) -> String? }`
  - Anthropic: parse `data:` lines of `content_block_delta` → `delta.text`. Ignore other events; `data: [DONE]` not used (Anthropic ends via `message_stop`).
  - OpenAI/OpenRouter: parse `data:` lines → `choices[0].delta.content`; stop on `data: [DONE]`.

- [ ] Test: feeding representative SSE lines for each provider yields the concatenated assistant text; non-text events yield nil.
- [ ] Implement; run; commit `"Add streaming SSE decoding"`.

---

### Task 4: Context assembly (pure, TDD)

**Files:** Create `pockterm/AI/ContextBuilder.swift`; Test `pocktermTests/ContextBuilderTests.swift`

- `struct Attachment { let name: String; let contents: String }`
- `enum ContextBuilder { static func systemPrompt(terminalText: String, attachments: [Attachment], maxChars: Int) -> String }`
  - Assembles a system prompt embedding the (tail-capped) terminal text and each attachment (capped), labeled, within `maxChars` total; drops/truncates oldest-first when over budget.

- [ ] Test: total length ≤ maxChars; terminal text and attachment names present; oversized inputs truncated deterministically (keep the tail of terminal output).
- [ ] Implement; run; commit `"Add AI context assembly"`.

---

### Task 5: API-key storage + AISettings

**Files:** Create `pockterm/AI/AIKeyStore.swift`, `pockterm/Model/AISettings.swift`; Modify `AppContainer` + test containers.

- `struct AIKeyStore { let secretStore: SecretStore; func setKey(_:for:); func key(for:) -> String?; func removeKey(for:) }` (keyed by `provider.keychainKeyID`).
- `@Model final class AISettings { var activeProviderRaw: String; var model: String }` (single row; provider + chosen model). Register in containers.

- [ ] Test: set/read/remove a key round-trips via `InMemorySecretStore`; `AISettings` persists.
- [ ] Implement; run; commit `"Add AI key store and settings model"`.

---

### Task 6: AIClient (URLSession streaming)

**Files:** Create `pockterm/AI/AIClient.swift`

- `actor AIClient { func stream(_ request: ChatRequest, provider: AIProvider, apiKey: String) -> AsyncThrowingStream<String, Error> }` — POSTs the encoded body, reads `bytes` line-by-line, feeds `StreamDecoder`, yields text deltas. Surfaces HTTP errors (401 → "invalid key", etc.).

- [ ] Implement; build for simulator (no live network test in CI — verified via the UI against a real key).
- [ ] Commit `"Add AIClient streaming over URLSession"`.

---

### Task 7: Settings UI (keys, provider, model)

**Files:** Create `pockterm/Features/AI/AISettingsView.swift`; Modify `RootTabView` (replace the Settings placeholder or add access).

- Add/edit/remove a key per provider (SecureField), pick the active provider + model, and a "Test" button that does a 1-token request to validate.

- [ ] Implement; build; commit `"Add AI settings screen"`.

---

### Task 8: Chat UI + terminal integration

**Files:** Create `pockterm/Features/AI/AssistantView.swift`, `pockterm/Features/AI/AssistantModel.swift`; Modify `SessionTabsView` (entry point button).

- Chat transcript with streaming assistant text; an attachments row (add remote file via SFTP browser / local via `.fileImporter`; remove via a chip's ✕); send includes the active session's terminal text as context; a detected command suggestion offers "Insert into terminal" → `session.sendKeys`.
- Privacy note stating terminal text + attachments are sent to the chosen provider.

- [ ] Implement; build for simulator; run unit tests; build/install/launch on device `<DEVICE_UDID>`.
- [ ] Commit `"Add AI assistant chat with terminal + file context"`.

---

## Self-Review notes
- **Spec coverage:** API keys for 3 providers (T1,T5) ✓; terminal-text context (T4,T8) ✓; add/remove files (T8) ✓; streaming chat (T3,T6,T8) ✓; suggest/insert commands (T8) ✓; Keychain-only secrets (T5) ✓.
- **Deferred:** OpenRouter OAuth (user chose keys-only); non-text attachments (text extraction only); multi-session context (active session only).
