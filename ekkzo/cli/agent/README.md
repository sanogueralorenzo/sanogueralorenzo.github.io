# Agent CLI

`agent` is the local CLI entrypoint for provider selection and runtime execution.

## Commands

- `agent` or `agent run`: starts the engine with the configured provider.
- `agent chat`: starts the provider chat process.
- `agent health`: reports provider CLI availability + auth health across OpenAI, Anthropic, and Google.
- `agent conversations list`: lists conversations from all providers using the unified session contract.
- `agent conversations resume <id>`: resolves a session by id and executes the provider resume command.
- `agent conversations resume <id> --dry-run`: prints the resolved provider resume command without executing it.
- `agent conversations delete <id>`: deletes a session id across all providers.
- `agent conversations deleteAll`: deletes all conversations across all providers.
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

## Health Notes

`agent health` checks:

- OpenAI via `codex login status`
- Anthropic via `claude auth status`
- Google via `gemini --version` plus `~/.gemini/google_accounts.json` active account state

`agent health` contract returns provider statuses only:

- `connected`
- `auth_missing`
- `cli_missing`

## Chat Notes

`agent chat` currently has adapters for OpenAI, Anthropic, and Google:

- OpenAI: Codex App Server flow ([docs](https://developers.openai.com/codex/app-server))
- Anthropic: Claude stream-json flow (`claude -p --verbose --output-format stream-json --input-format stream-json`)
- Google: Gemini ACP flow (`gemini --acp`)

The chat command uses the default CLI binaries on your `PATH`:

- `codex app-server` for `openai`
- `claude` for `anthropic`
- `gemini --acp` for `google`

Runtime behavior for now:

- Incoming JSON-RPC is forwarded from chat stdin to the selected provider runtime.
- Chat stdout emits mapped status events only.
- All provider protocol messages and non-JSON log lines are ignored at chat output.

## Chat Contract

The chat turn event contract lives in:

`src/bridge/contracts/turn_events.rs`

It exposes:

- start event: `provider`, `id`, `status=thinking`
- end event: `provider`, `id`, `status` (`completed|interrupted|failed`), `answer`, optional `error`

## Conversations Notes

`agent conversations` uses provider-local stores:

- OpenAI: `~/.codex/session_index.jsonl` and `~/.codex/sessions/**/rollout-*.jsonl`
- Anthropic: `~/.claude/projects/**/*.jsonl`
- Google: `~/.gemini/tmp/**/session-*.json`
