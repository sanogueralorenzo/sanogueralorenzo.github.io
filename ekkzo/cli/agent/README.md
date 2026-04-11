# Agent CLI

`agent` is the local CLI entrypoint for provider selection and runtime execution.

## Commands

- `agent` or `agent run`: starts the engine with the configured provider.
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
