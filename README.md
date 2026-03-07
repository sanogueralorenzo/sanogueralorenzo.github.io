## Intro

**sanogueralorenzo.github.io** is a monorepo for local AI tooling, product apps, and orchestration harnesses.

---

## Quickstart

### Install local tools from source

```shell
./install.sh
```

### Run core CLIs

```shell
codex-auth list
codex-sessions list --all
codex-remote status
```

## Monorepo Index

- `codex-auth`: Swift CLI for Codex auth profile management.
- `codex-sessions`: Rust CLI for local Codex session lifecycle.
- `codex-remote`: TypeScript Telegram bridge to Codex app-server.
- `codex-menubar`: macOS menu bar app orchestrating local Codex tooling.
- `codex-agents`: autonomous/headless agent workflow contract.
- `overlay`: Android blackout overlay utility app.
- `voice`: Android on-device voice keyboard (ASR + rewrite).
- `site`: static site content and generation.

## Harness Engineering Model

- This monorepo is harness-first: automate repetitive engineering loops with explicit contracts, bounded permissions, deterministic retries, and observable outputs.
- Reference: [Harness Engineering](https://openai.com/index/harness-engineering/).
- Practical defaults:
  - Keep each module independently runnable.
  - Prefer CLIs/scripts as stable integration boundaries.
  - Keep state explicit and recoverable.
