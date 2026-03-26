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
codex-core agents task run TS-123 --json
codex-core agents spike run TS-123 --json
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
  - `codex-core agents ...` manages local task and review workflows plus worker loops.
  - Primary verbs: `config init|show|available-repos|available-projects|set-allowed-repos|set-allowed-projects|set-project-repo-mappings|set-review-mode|clear-allowed-repos|clear-allowed-projects|clear-project-repo-mappings`, `task list|run|jobs|show`, `spike run`, `worker start|loop`, `review list|run|jobs|show`.
  - `worker loop` starts a fresh `codex exec` run on every iteration; continuity is expected to come from your plan/prompt files, not from thread resume.
  - Important loop flags: `--prompt-file`, `--cd`, `--interval-seconds`, `--max-iterations`, `--stop-phrase`, `--once`, `--model`, `--full-auto`, `--dangerously-bypass-approvals-and-sandbox`, `--skip-git-repo-check`.
  - `config show --json` returns the current agents settings, including `review_mode`, `allowed_repos`, `allowed_projects`, and `project_repo_mappings`.
  - `config available-repos --json` returns available personal and organization repos from `gh` where your `viewerPermission` is `WRITE`, `MAINTAIN`, or `ADMIN`.
  - `config available-projects --json` returns Jira projects visible to your `acli jira` account, reduced to each project's numeric `id` plus Jira `key`.
  - `config set-review-mode publish|pending` sets the default review posting mode used by `review run`.
  - `config set-allowed-projects <id>...` stores the Jira project filter list used by agent clients; `clear-allowed-projects` removes that filter.
  - `config set-project-repo-mappings <project-id>=<owner/repo>...` stores the Jira-project to GitHub-repo mapping used by task automation; `clear-project-repo-mappings` removes all mappings.
  - `task list --json` returns Jira work items assigned to `currentUser()` in open sprints, filtered by `allowed_projects` when configured and reduced to `ticket`, `summary`, Jira URL, repo mapping, status, and priority. Tasks only appear for Jira projects that also have a configured `project_repo_mapping`.
  - `task run <ticket> --json` loads the Jira issue through `acli jira`, updates the cached repo `main`, creates a disposable worktree under `~/.codex/agents/worktrees/tasks`, runs `codex exec` to implement the ticket and open a draft PR, then removes the worktree when the run exits.
  - `task jobs --json` lists persisted task jobs from `~/.codex/agents/tasks`, including branch, current step, Jira URL, PR URL, summary, and terminal error.
  - `task show <job-id> --json` shows one persisted task job snapshot from `~/.codex/agents/tasks/<job-id>.json`.
  - `spike run <ticket> --json` loads the Jira issue through `acli jira`, also loads the latest Jira comments for context, resolves its mapped GitHub repository from `project_repo_mappings`, updates cached `main`, creates a disposable worktree under `~/.codex/agents/spikes/worktrees`, runs `codex exec` in read-only investigation mode, and only posts a Jira comment when the spike produces materially new information beyond the existing description and comments.
  - `review list --json` returns open PRs across your personal repos and orgs from `gh`, filtered by `allowed_repos` when configured and ordered by `created_at` newest first.
  - `review run <pr-url|owner/repo#number>` reuses a cached repo under `~/.codex/agents/repos/<owner>/<repo>`, creates a per-run worktree under `~/.codex/agents/worktrees`, fetches upstream review prompts from `openai/codex` `main`, runs `codex exec` with those prompts unchanged, validates findings against changed diff lines on both left and right sides, and supports `--publish-mode publish|pending` (defaulting to `config.review_mode`).
  - In `publish` mode, findings get Shields priority badges in the heading (`P1` red, `P2` yellow, `P3` grey) without repeating a leading textual `[P1]/[P2]/[P3]` tag, post inline GitHub review comments via `gh` against the latest PR head SHA when possible, and fall back to separate top-level PR comments with direct file+line hyperlinks when inline placement is not possible.
  - In `pending` mode, inline-commentable findings are created inside one pending GitHub review and non-inline findings are grouped into that review body so you can edit or submit the draft manually from GitHub later.
  - `review run` persists job state under `~/.codex/agents/reviews/<review-id>` and returns per-comment failure reasons in JSON/default output when posting still fails.
  - `review jobs --json` lists persisted review jobs from `~/.codex/agents/reviews` and includes a client-facing derived `status` (`published`, `needs_attention`, `in_progress`) plus `current_step` for the active phase.
  - `review show <review-id> --json` shows one persisted review job snapshot, including the derived `status` and `current_step`.
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
