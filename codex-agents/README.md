## Intro

**Codex Agents** is a basic local CLI for tracking ticket tasks and running a lightweight worker loop.

## Quickstart

Requires Rust toolchain (`cargo`) on `PATH`.

```shell
./scripts/install.sh
codex-agents config init
codex-agents task create TS-1234
codex-agents task list
codex-agents worker start --once
```

## Reference

### CLI

```shell
codex-agents --help
codex-agents task --help
```

### Commands (`codex-agents --help`)

```text
config  Initialize local codex-agents configuration.
task    Create/list/show tasks.
worker  Start autonomous worker loop.
help    Print this help output.
```

### Task Commands

```shell
codex-agents task create <TICKET-KEY>
codex-agents task list
codex-agents task show <TICKET-KEY>
```

### Worker Commands

```shell
codex-agents worker start
codex-agents worker start --once
codex-agents worker start --interval-seconds 60
```

Behavior:
- Worker scans local pending tasks and prints the next task suggestion.
- `--once` runs one cycle and exits.
- Default polling interval is 30 seconds.

### Storage

- Default home: `~/.codex/agents`
- Override home: `CODEX_AGENTS_HOME=/custom/path`
- Config file: `~/.codex/agents/config.env`
- Task files: `~/.codex/agents/tasks/*.task`
