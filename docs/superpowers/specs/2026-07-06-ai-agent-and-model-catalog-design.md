# AI Agent & Dynamic Model Catalog — Design

Date: 2026-07-06
Status: approved (design approved in-session by John)

## Goal

Turn pockterm's AI chat into a tool-using agent, and make the model picker
self-maintaining: model lists fetched from each provider in the background at
low frequency, with a last-known-good cache so the user never sees an empty
list. Providers: Anthropic, OpenAI, OpenRouter, Hugging Face. Text-first
models are in scope; other modalities are a bonus, not a requirement.

No agent library: the Swift ecosystem's options (SwiftAgent, swift-llm,
langchain-swift) are immature, and the agent loop is small. The real work —
pockterm-specific tools over SSH/SFTP — would sit outside any library anyway.
Only two wire formats exist across the four providers: Anthropic Messages and
OpenAI Chat Completions (OpenRouter and the Hugging Face router are both
OpenAI-compatible).

## Part 1 — Providers & dynamic model lists

### New provider: Hugging Face

Add `.huggingFace` to `AIProvider`:

- Chat: `POST https://router.huggingface.co/v1/chat/completions` (streamed,
  OpenAI wire format).
- Models: `GET https://router.huggingface.co/v1/models` (same
  `{"data":[{"id":…}]}` shape as the others).
- Auth: `Authorization: Bearer <HF token>`.
- Token-limit field: `max_tokens`. Only `.openai` sends
  `max_completion_tokens` (OpenAI deprecated `max_tokens`; gpt-5/o-series
  reject it). OpenRouter and HF keep `max_tokens` per their schemas.
- Default model: a strong open text model (e.g. `openai/gpt-oss-120b`).

### Background refresh (low frequency)

New `ModelCatalogRefresher` (@MainActor, owned by the app root):

- Trigger: app launch and foreground activation (`scenePhase == .active`).
  No timers, no BGTaskScheduler — foreground-triggered refresh is the
  reliable low-frequency pattern on iOS.
- For each provider that has a stored API key and whose cache is older than
  24 hours, fetch the model list once (no retry storm; a single failure waits
  for the next trigger).
- Persist `modelCatalog.lastRefreshed.<provider>` alongside the cached list.

### Last-known-good guarantee

- Cache is only replaced on a successful, non-empty fetch; failures never
  clear it. (Existing `ModelCatalog` behavior, kept.)
- The picker's "list never changes under your finger" behavior is kept: fast
  responses replace the visible list, slow ones land behind the banner.
- Seed defaults: when there is no cache and no key yet, the picker shows the
  provider's `defaultModel` so the list is never empty.

### Text-first filtering

- OpenRouter: models endpoint includes `architecture.modality`; keep models
  whose output modality includes text.
- OpenAI: drop non-chat id families (`whisper*`, `tts*`, `dall-e*`,
  `*embedding*`, `*moderation*`, `davinci/babbage` legacy).
- Anthropic, Hugging Face router: already chat-model lists; no filter.

## Part 2 — The agent

### Types

- `ToolSpec`: name, description, JSON-schema parameters (`[String: Any]`).
- `ChatMessage` grows: role `tool`, optional `toolCalls: [ToolCall]`
  (id, name, argumentsJSON) on assistant messages, and `toolCallID` on tool
  messages.
- `RequestEncoder` renders `[ToolSpec]` into Anthropic `tools`
  (`input_schema`) and OpenAI `tools` (`{"type":"function","function":…}`),
  and encodes assistant tool-call turns and tool-result turns in each format
  (Anthropic: `tool_use` / `tool_result` content blocks; OpenAI: `tool_calls`
  / role `tool` messages).
- `StreamDecoder` assembles streamed tool-call fragments: OpenAI
  `choices[].delta.tool_calls[]` (arguments arrive as string chunks);
  Anthropic `content_block_start` (`tool_use`) + `input_json_delta`. Output:
  text deltas plus, at stream end, complete `ToolCall`s and a stop reason.

### Agent loop

`AgentLoop` drives: send conversation + tool specs → stream assistant reply →
if tool calls were requested: for each, ask `ApprovalPolicy`, execute via
`ToolExecutor`, append tool-result message → repeat. Stops when the model
returns no tool calls, on user cancel, or at a hard cap of 20 iterations
(cap surfaced in chat as "stopped after 20 steps"). Every command, approval,
and result renders as a card in the transcript.

### Tools

| Tool | Does | Mutating |
|---|---|---|
| `run_command` | Execute a shell command on the connected host, return stdout+stderr (truncated to a budget) | depends |
| `read_file` | Read a remote file over SFTP | no |
| `write_file` | Create/overwrite a remote file over SFTP | yes |
| `list_files` | List a remote directory over SFTP | no |
| `open_session` | Open a session to a saved host in pockterm | yes (app) |
| `save_snippet` | Save a command snippet in pockterm | yes (app) |

`run_command` uses a separate exec channel on the existing SSH connection —
clean output capture, nothing typed into the user's visible terminal. The
command and its output appear as a chat card.

### Approval

New AI setting `agentApproval`, three modes:

1. **Confirm everything** (default) — every tool call shows an approval card
   (Run / Deny) before executing.
2. **Confirm risky only** — read-only tools and commands classified read-only
   auto-run; mutating ones ask. Risk classifier is a conservative heuristic
   (deny-list of mutating patterns: `rm`, `sudo`, redirection, `mv`, `chmod`,
   package managers, etc.; unknown ⇒ risky).
3. **Auto-run** — everything executes; transcript is the audit trail.

Denying a tool call sends a "user declined" tool result so the model can
adjust rather than the loop dying.

### Testing

- Encoder/decoder: pure unit tests per provider for tool specs, tool-call
  turns, tool-result turns, streamed fragment assembly.
- Agent loop: scripted fake client (protocol over `AIClient`) exercising
  multi-step runs, denial, cancel, iteration cap.
- Risk classifier: table-driven tests.
- Tool executors are protocol-backed (like `SecretStore`) so the loop is
  testable without SSH.

## Build order

Part 1 first (small, independently shippable), then Part 2.
