## Intro

**Codexhub** is a unified CLI for:
- app-server passthrough (`codex app-server`)
- local session/thread maintenance commands
- non-interactive `codex exec` wrappers

## Quickstart

```shell
./scripts/install.sh
codexhub rpc --listen stdio://
codexhub sessions ls --json
codexhub noninteractive run --help
```

## Reference

- App-server passthrough:
  - `codexhub rpc --listen stdio://` forwards to `codex app-server --listen stdio://`.
- Sessions commands:
  - `codexhub sessions ...` manages session lifecycle, titles, merge, and cleanup.
  - Primary verbs: `ls`, `show`, `rm`, `archive`, `restore`, `prune`.
  - `sessions ls` defaults to `--sort-by updated_at` (newest first).
  - `watch prune` runs scheduled prune passes.
  - Thread-title watcher rewrites titles when empty or when current title matches the first user message.
- Noninteractive wrappers:
  - `codexhub noninteractive run` wraps `codex exec --json`.
  - `codexhub noninteractive resume` wraps `codex exec resume --json`.
  - `codexhub noninteractive review` wraps `codex exec review --json`.
  - Wrapper-standardized flags:
    - `--prompt | --prompt-file | --prompt-stdin` (mutually exclusive)
    - `--result-json <path>` with `status`, `exit_code`, `thread_id`, `final_message`, `stderr`
    - `--raw-jsonl` to print upstream JSONL events
    - `--emit-events` to mirror events to stderr
