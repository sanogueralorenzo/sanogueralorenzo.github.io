## Intro

**Codex App Server** provides a dedicated `codex-app-server` CLI that forwards arguments and stdio to `codex app-server`.

## Quickstart

```shell
./scripts/install.sh
codex-app-server --listen stdio://
```

## Reference

- The binary is a 1:1 passthrough to `codex app-server`.
- Every flag after `codex-app-server` is forwarded unchanged to `codex app-server`.
