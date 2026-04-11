# Agent CLI

`agent` is the local CLI entrypoint for provider selection and runtime execution.

## Commands

- `agent` or `agent run`: starts the engine with the configured provider.
- `agent bridge`: starts the provider bridge process.
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

To override the config directory path, set:

`AGENT_CONFIG_PATH=/path/to/config/dir`

## Bridge Notes

`agent bridge` currently has adapters for OpenAI and Google:

- OpenAI: Codex App Server flow ([docs](https://developers.openai.com/codex/app-server))
- Google: Gemini ACP flow (`gemini --acp`)

The bridge uses the default CLI binaries on your `PATH`:

- `codex app-server` for `openai`
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
