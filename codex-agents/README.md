## Intro

**Codex Agents** is a local CLI for tracking ticket tasks plus Ralph-style loop execution on top of `codex exec`.

## Quickstart

Requires Rust toolchain (`cargo`) on `PATH`.

```shell
./scripts/install.sh
codex-agents config init
codex-agents task create TS-1234
codex-agents task list
codex-agents worker loop "Implement the next task. Respond with RALPH_DONE when complete."
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
codex-agents worker loop "Implement X and respond with RALPH_DONE when done"
codex-agents worker loop --prompt-file ./loop-prompt.txt --max-iterations 10
```

Behavior:
- Worker scans local pending tasks and prints the next task suggestion.
- `--once` runs one cycle and exits.
- Default polling interval is 30 seconds.

### Ralph Loop (`codex exec`)

`worker loop` runs `codex exec` repeatedly using the same prompt and reuses session context when possible.

Common options:
- `--prompt-file <FILE>`: read loop prompt from file.
- `--cd <DIR>`: working directory for `codex exec` (default: current directory).
- `--interval-seconds <N>`: sleep between iterations (default: 30).
- `--max-iterations <N>`: stop after N iterations.
- `--stop-phrase <TEXT>`: stop when final assistant message contains this text (default: `RALPH_DONE`).
- `--model <MODEL>`: pass model override to `codex exec`.
- `--full-auto`, `--dangerously-bypass-approvals-and-sandbox`, `--skip-git-repo-check`: passed through to `codex exec`.

### Storage

- Default home: `~/.codex/agents`
- Override home: `CODEX_AGENTS_HOME=/custom/path`
- Config file: `~/.codex/agents/config.env`
- Task files: `~/.codex/agents/tasks/*.task`
