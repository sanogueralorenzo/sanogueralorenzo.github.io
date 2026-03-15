## Intro

**Codex App Server** is a unified CLI for:
- app-server passthrough (`codex app-server`)
- local session/thread maintenance commands
- non-interactive `codex exec` wrappers

## Quickstart

```shell
./scripts/install.sh
codex-app-server rpc --listen stdio://
codex-app-server sessions list --json
codex-app-server noninteractive run --help
```

## Reference

- App-server passthrough:
  - `codex-app-server rpc --listen stdio://` forwards to `codex app-server --listen stdio://`.
  - `codex-app-server rpc app-server --listen stdio://` is also accepted.
- Sessions commands:
  - `codex-app-server sessions ...` manages session lifecycle, titles, merge, and cleanup.
  - Thread-title watcher rewrites titles when empty or when current title matches the first user message.
- Noninteractive wrappers:
  - `codex-app-server noninteractive run` wraps `codex exec --json`.
  - `codex-app-server noninteractive resume` wraps `codex exec resume --json`.
  - `codex-app-server noninteractive review` wraps `codex exec review --json`.
  - Wrapper-standardized flags:
    - `--prompt | --prompt-file | --prompt-stdin` (mutually exclusive)
    - `--result-json <path>` with `status`, `exit_code`, `thread_id`, `final_message`, `stderr`
    - `--raw-jsonl` to print upstream JSONL events
    - `--emit-events` to mirror events to stderr
