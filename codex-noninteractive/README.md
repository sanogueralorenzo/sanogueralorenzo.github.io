## Intro

**Codex Noninteractive** is a script/CI-friendly wrapper around `codex exec`.

## Quickstart

```shell
./scripts/install.sh
```

## Auth Modes

Use one of these two auth paths depending on where you run:

| Mode | Use this when | Setup |
| --- | --- | --- |
| Codex subscription login | Local/dev machine with your Codex account session | `codex login` |
| API key (`CODEX_API_KEY`) | CI/headless automation or ephemeral machines | `export CODEX_API_KEY="<your-openai-api-key>"` |

### Local Subscription Auth (Recommended for local runs)

```shell
unset CODEX_API_KEY OPENAI_API_KEY
codex login
codex login status
codex-noninteractive run --prompt "Reply with exactly OK"
```

### API Key Auth (Recommended for CI)

```shell
export CODEX_API_KEY="<your-openai-api-key>"
codex-noninteractive run --prompt "Reply with exactly OK"
```

## Reference

### CLI

```shell
codex-noninteractive --help
codex-noninteractive run --help
codex-noninteractive resume --help
```

### Commands (`codex-noninteractive --help`)

```text
run     Start a new non-interactive Codex exec turn
resume  Resume an existing Codex exec thread non-interactively
help    Print this message or the help of the given subcommand(s)
```

### Runtime Behavior

- The wrapper always runs `codex exec --json`.
- Final assistant text is emitted to stdout.
- `--result-json <PATH>` writes a machine-readable summary for scripts/CI:
  - `status`: `completed | failed`
  - `exit_code`: Codex process exit code
  - `thread_id`: parsed from `thread.started` event when present
  - `final_message`: final assistant message text
  - `stderr`: captured codex stderr output
- `--prompt`, `--prompt-file`, and `--prompt-stdin` are mutually exclusive.
- `resume` requires either `<thread_id>` or `--last`.

### CI Auth

- `codex exec` supports headless auth with `CODEX_API_KEY`.
- This is the preferred path for CI runners.
- Example:

```shell
export CODEX_API_KEY="<your-openai-api-key>"
codex-noninteractive run \
  --prompt "Return strict JSON only: {\"status\":\"ok\"}" \
  --output-schema ./schema.json \
  --result-json ./codex-result.json
```
