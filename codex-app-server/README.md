## Intro

**Codex App Server** is a unified CLI for:
- app-server passthrough (`codex app-server`)
- local session/thread maintenance commands

## Quickstart

```shell
./scripts/install.sh
codex-app-server --listen stdio://
codex-app-server sessions list --json
```

## Reference

- App-server passthrough:
  - `codex-app-server --listen stdio://` forwards to `codex app-server --listen stdio://`.
  - `codex-app-server app-server --listen stdio://` is also accepted.
- Sessions commands:
  - `codex-app-server sessions ...` manages session lifecycle, titles, merge, and cleanup.
