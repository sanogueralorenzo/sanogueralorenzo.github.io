## Intro

**Codex Core** is a unified CLI for:
- app-server passthrough (`codex app-server`)
- auth profile management
- local agent workflows
- local session/thread maintenance commands
- non-interactive `codex exec` wrappers

## Quickstart

```shell
./scripts/install.sh
codex-core app-server --listen stdio://
codex-core auth list --plain
codex-core agents task list
codex-core sessions ls --json
codex-core noninteractive run --help
```

## Reference

- App-server passthrough:
  - `codex-core app-server --listen stdio://` forwards to `codex app-server --listen stdio://`.
- Auth commands:
  - `codex-core auth ...` manages profiles, current auth selection, and the auth watcher.
  - Primary verbs: `save`, `use`, `list`, `current`, `remove`, `watch`.
  - `save` reads the current `auth.json` by default; use `--path <auth.json>` only when importing from another file.
  - State lives under `~/.codex/auth`, including `profiles/`, `active-account-id`, `watch.pid`, and `watch.log`.
- Agents commands:
  - `codex-core agents ...` manages local task files and worker loops.
  - Primary verbs: `config init|show|set-project-home|clear-project-home|available-repos|set-allowed-repos|clear-allowed-repos`, `task create|list|show`, `worker start|loop`, `review list|run`.
  - `worker loop` starts a fresh `codex exec` run on every iteration; continuity is expected to come from your plan/prompt files, not from thread resume.
  - Important loop flags: `--prompt-file`, `--cd`, `--interval-seconds`, `--max-iterations`, `--stop-phrase`, `--once`, `--model`, `--full-auto`, `--dangerously-bypass-approvals-and-sandbox`, `--skip-git-repo-check`.
  - `config show --json` returns the current agents settings, including `project_home` and `allowed_repos`.
  - `config available-repos --json` returns available personal and organization repos from `gh` where your `viewerPermission` is `WRITE`, `MAINTAIN`, or `ADMIN`.
  - `review list --json` returns open PRs across your personal repos and orgs from `gh`, filtered by `allowed_repos` when configured.
  - `review run <pr-url|owner/repo#number>` uses `project_home/<owner>/<repo>` for persistent checkouts when configured, otherwise it uses `/tmp` and deletes the clone after the run; then it fetches upstream review prompts from `openai/codex` `main`, runs `codex exec` with those prompts unchanged, validates findings against changed diff lines on both left and right sides, and posts inline GitHub review comments via `gh`.
  - On macOS, worker commands try to enable `caffeinate` while running.
  - State defaults to `~/.codex/agents` and can be overridden with `CODEX_AGENTS_HOME`; settings are stored in `config.json`.
- Sessions commands:
  - `codex-core sessions ...` manages session lifecycle, titles, merge, and cleanup.
  - Primary verbs: `ls`, `show`, `rm`, `archive`, `restore`, `prune`.
  - `sessions ls` defaults to `--sort-by updated_at` (newest first).
  - `watch prune` runs scheduled prune passes.
  - Thread-title watcher rewrites titles when empty or when current title matches the first user message.
- Noninteractive wrappers:
  - `codex-core noninteractive run` wraps `codex exec --json`.
  - `codex-core noninteractive resume` wraps `codex exec resume --json`.
  - `codex-core noninteractive review` wraps `codex exec review --json`.
  - Wrapper-standardized flags:
    - `--prompt | --prompt-file | --prompt-stdin` (mutually exclusive)
    - `--result-json <path>` with `status`, `exit_code`, `thread_id`, `final_message`, `stderr`
    - `--raw-jsonl` to print upstream JSONL events
    - `--emit-events` to mirror raw JSONL events to stderr
