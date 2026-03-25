## Intro

**Codex Menubar** is a macOS menu bar app that orchestrates local Codex tooling.

## Quickstart

```shell
./scripts/install.sh
```

## Reference

### Integrations

- Required: `codex-core`
- Optional: `codex-remote`

### Runtime Behavior

- Launch starts `codex-core auth watch start`.
- Launch starts `codex-core sessions watch thread-titles start`.
- Launch starts `codex-remote start --plain` only when remote auto-start has been enabled by a prior successful `Remote -> Start`.
- Launch starts background auto-remove runs only when a day+mode selection is configured.
- Launch agent executable path is fixed to `/Applications/Codex Menu Bar.app`.
- Menu includes `Codex` as the first action; it launches Codex if needed or brings it to focus when already running.
- Menu section labels are `Agents`, `Remote`, `Profiles`, and `Threads`.
- `Remote -> Start` enables remote auto-start for future app launches.
- `Remote -> Stop` disables remote auto-start for future app launches.
- `Agents` includes a `View` submenu that combines running + recent tasks.
- In `Agents -> View`, recent task labels are prefixed by status: `•` in progress, `✓` completed, `X` failed.
- `Agents` includes a `Review` submenu populated from both `codex-core agents review jobs --json` and `codex-core agents review list --json`.
- `Agents -> Review` keeps the open PR list and prefixes matching PR rows with bracketed persisted review job status markers: `[-]` in progress, `[X]` needs attention, `[✓]` published, `[ ]` when no persisted review exists yet.
- `Agents -> Review` groups pull requests by repository; clicking a repository row opens its GitHub page.
- `Agents -> Review` shows PR rows as `#<number> <title>`.
- The menubar watches `~/.codex/agents/reviews` (or `CODEX_AGENTS_HOME/reviews`) so review status markers update from persisted job writes instead of timer polling.
- `Agents -> Settings` opens immediately, then loads GitHub repos in the background through `codex-core agents config ...`.
- `Agents -> Settings` shows an `Integrations` section with `gh` and `acli` status pills plus setup instructions when needed.
- `Agents -> Settings` centers the `gh` and `acli` labels inside their rounded status pills.
- `Agents -> Settings` normalizes integration details to account labels like `GitHub: <username>` and `Jira: <account>`.
- `Agents -> Settings` verifies `acli` through a read-only Jira command so the status reflects actual Jira access instead of `acli auth status`.
- `Agents -> Settings` shows a `GitHub Repos` section for review filtering.
- `Agents -> Settings` includes a local repository search field that filters the visible repo list as you type.
- `Agents -> Settings` shows a loading hint for GitHub repos, then switches to the repo-selection hint after load completes.
- Selecting an item in `Agents -> Review` runs `codex-core agents review run <pr>` and posts inline findings derived from upstream `openai/codex` review prompts on GitHub `main`.
- Review completion alerts include the persisted review job ID from `~/.codex/agents/reviews/<review-id>`.
- Review completion alerts include per-comment failure reasons when inline comment posting is skipped or rejected.
- Quit stops managed background processes, then terminates the Codex macOS app before app termination.
- CLI executable lookup is deterministic and only checks `/opt/homebrew/bin` and `/usr/local/bin`.
- Managed CLI subprocesses run with a deterministic environment that includes `/opt/homebrew/bin`, `/usr/local/bin`, and standard system paths.
- Profile management section is labeled `Profiles` and includes profile switch/remove actions plus `Add`.
- When profile listing fails transiently, the menu preserves the last loaded profile list so logged-out state can still show known profiles as unselected.
- Threads menu includes:
  - `Floating` bold header row plus `Start`, followed by a divider.
  - `Auto-Remove` bold title row clears the saved day+mode selection (disables auto-remove).
  - `Now` closes Codex only when running, executes immediate `prune --older-than-days 0 --mode delete`, then reopens Codex.
  - `Auto-Remove` window: `1 day`, `3 days`, `7 days` (single-select checkmark)
  - Each day option has a submenu with `Archive` and `Delete`.
- Selecting a day+mode persists immediately and restarts auto-remove runs.

### Storage

- `/Applications/Codex Menu Bar.app`
- `~/Library/LaunchAgents/io.github.sanogueralorenzo.codex.menubar.plist`
- `/tmp/codex-menu-menubar.out.log`
- `/tmp/codex-menu-menubar.err.log`
