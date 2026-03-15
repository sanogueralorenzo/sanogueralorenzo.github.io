## Intro

**Codex Agents** defines headless Codex engineering workflows for task execution loops.

## Quickstart

```shell
./scripts/install.sh
```

## Reference

### CLI

```shell
codex-agents --help
codex-agents task --help
codex-agents noninteractive --help
codex-agents noninteractive run --help
```

### Commands (`codex-agents --help`)

```text
config  Initialize local codex-agents configuration.
noninteractive  Run standardized non-interactive Codex wrappers.
task    Create/list/show tasks.
worker  Start autonomous worker loop.
help    Print this help output.
```

### Noninteractive Wrapper

- `noninteractive run` wraps `codex exec --json`.
- `noninteractive resume` wraps `codex exec resume --json`.
- `noninteractive review` wraps `codex exec review --json`.
- Wrapper-standardized flags:
  - `--prompt | --prompt-file | --prompt-stdin` (mutually exclusive)
  - `--result-json <path>` normalized output contract:
    - `status`
    - `exit_code`
    - `thread_id`
    - `final_message`
    - `stderr`
  - `--raw-jsonl` pass raw Codex JSONL events to stdout
  - `--emit-events` mirror parsed JSONL events to stderr
- Remaining args are forwarded to upstream `codex exec` subcommands.

### Storage

- No module-specific persistent storage is implemented yet.
