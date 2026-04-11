# Agent CLI

`agent` is the local CLI entrypoint for provider selection and runtime execution.

## Commands

- `agent` or `agent run`: starts the engine with the configured provider.
- `agent bridge`: starts the provider bridge process.
- `agent sessions list`: lists sessions from all providers using the unified session contract.
- `agent sessions resume <id>`: resolves a session by id and executes the provider resume command.
- `agent sessions resume <id> --dry-run`: prints the resolved provider resume command without executing it.
- `agent sessions delete <id>`: deletes a session id across all providers.
- `agent sessions deleteAll`: deletes all sessions across all providers.
- `agent providers`: prints current and available providers.
- `agent providers list`: lists available providers.
- `agent providers current`: prints the selected provider.
- `agent providers set <provider>`: persists the provider selection.

## Supported Providers

- `openai` (default)
- `anthropic`
- `google`

## Config

By default, provider selection is stored at:

`~/.config/agent/provider`

## Bridge Notes

`agent bridge` currently has adapters for OpenAI, Anthropic, and Google:

- OpenAI: Codex App Server flow ([docs](https://developers.openai.com/codex/app-server))
- Anthropic: Claude stream-json flow (`claude -p --verbose --output-format stream-json --input-format stream-json`)
- Google: Gemini ACP flow (`gemini --acp`)

The bridge uses the default CLI binaries on your `PATH`:

- `codex app-server` for `openai`
- `claude` for `anthropic`
- `gemini --acp` for `google`

Runtime behavior for now:

- Incoming JSON-RPC is forwarded from bridge stdin to the selected provider runtime.
- Bridge stdout emits only mapped contract events (`turn.started`, `turn.completed`).
- All provider protocol messages and non-JSON log lines are ignored at bridge output.

## Bridge Contract

The bridge turn event contract lives in:

`src/bridge/contracts/turn_events.rs`

It exposes:

- `turn.started` with `threadId` and `state=in_progress`
- `turn.completed` with `threadId`, `status`, `answer`, and optional `error`

## Sessions Notes

`agent sessions` uses provider-local stores:

- OpenAI: `~/.codex/session_index.jsonl` and `~/.codex/sessions/**/rollout-*.jsonl`
- Anthropic: `~/.claude/projects/**/*.jsonl`
- Google: `~/.gemini/tmp/**/session-*.json`
