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

`agent bridge` currently has an adapter for OpenAI only, and follows the Codex App Server flow:

https://developers.openai.com/codex/app-server

The bridge uses `codex app-server` from the default `codex` CLI on your PATH.
Runtime behavior for now:

- Incoming JSON-RPC is forwarded from bridge stdin to `codex app-server`.
- Bridge stdout emits only mapped contract events (`turn.started`, `turn.completed`).
- All other Codex protocol messages are ignored at bridge output.

## Bridge Contract

The bridge turn event contract lives in:

`src/bridge/contracts/turn_events.rs`

It exposes:

- `turn.started` with `threadId` and `state=in_progress`
- `turn.completed` with `threadId`, `status`, `answer`, and optional `error`
