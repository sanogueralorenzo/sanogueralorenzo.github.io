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
- Install stops the loaded LaunchAgent first, replaces the app bundle, then bootstraps the LaunchAgent again so relaunch stays single-instance and auto-start remains configured.
- Menu includes `Codex` as the first action; it launches Codex if needed or brings it to focus when already running.
- Global shortcut `Control-Option-C` opens the native menubar menu regardless of Caps Lock state.
- Menu section labels are `Agents`, `Remote`, `Profiles`, and `Threads`.
- `Remote -> Start` enables remote auto-start for future app launches.
- `Remote -> Stop` disables remote auto-start for future app launches.
- `Agents` includes a `View` submenu populated from `codex-core agents task jobs --json`.
- `Agents -> View` shows persisted task jobs grouped into running first and recent after; each task job submenu exposes `Open Ticket`, `Open PR` when available, and `Re-run Task`.
- Task job rows use status prefixes: `·` in progress, `✓` completed, `X` failed.
- `Agents` includes a `Task` submenu populated from `codex-core agents task list --json`.
- `Agents -> Task` lists only Jira work items assigned to the current user in the current sprint, filtered by the selected Jira projects from Settings.
- `Agents -> Task` only includes Jira projects that also have a selected GitHub repository mapping in Settings.
- `Agents -> Task` groups work items by mapped GitHub repository; clicking a repository row opens its GitHub page.
- Selecting an item in `Agents -> Task` runs `codex-core agents task run <ticket>`, which updates cached `main`, creates a disposable worktree, runs `codex exec` to implement the ticket and open a PR, then removes the worktree on exit.
- `Agents` includes a `Review` submenu populated from both `codex-core agents review jobs --json` and `codex-core agents review list --json`.
- `Agents -> Review` keeps the open PR list and prefixes matching PR rows with persisted review job status markers: `·` in progress, `X` needs attention, `✓` published. PRs with no persisted review job have no prefix.
- `Agents -> Review` groups pull requests by repository; clicking a repository row opens its GitHub page.
- `Agents -> Review` shows PR rows as `#<number> <title>`.
- The menubar watches `~/.codex/agents/reviews` (or `CODEX_AGENTS_HOME/reviews`) so review status markers update from persisted job writes instead of timer polling.
- The menubar also watches `~/.codex/agents/tasks` (or `CODEX_AGENTS_HOME/tasks`) so task status markers update from persisted task job writes.
- `Agents -> Settings` opens immediately, then loads GitHub repositories and Jira projects in the background through `codex-core agents config ...`.
- `Agents -> Settings` loads GitHub repositories and Jira projects independently, so one source can still render even if the other fails.
- `Agents -> Settings` shows an `Integrations` section with `gh` and `acli` status pills plus setup instructions when needed.
- `Agents -> Settings` centers the `gh` and `acli` labels inside their rounded status pills.
- `Agents -> Settings` normalizes integration details to account labels like `GitHub: <username>` and `Jira: <account>`.
- `Agents -> Settings` verifies `acli` through a read-only Jira command so the status reflects actual Jira access instead of `acli auth status`.
- `Agents -> Settings` includes a `Review Mode` section with `Publish` and `Pending`, saved through `codex-core agents config set-review-mode`.
- `Agents -> Settings` shows a `GitHub Repositories` tab for review filtering.
- `Agents -> Settings` uses a segmented selector to switch between `GitHub Repositories`, `Jira Projects`, and `Project Repos`, reusing one shared search field and one larger list area.
- `Agents -> Settings` shows loading hints for the active source, then switches to the corresponding selection hint after load completes.
- `Agents -> Settings` shows a `Jira Projects` section so you can include or exclude projects visible to your `acli jira` account, displaying each project by its Jira key and persisting the numeric project id used to filter the `Agents -> Task` submenu.
- `Agents -> Settings -> Project Repos` shows one row per selected Jira project and lets you map it to one of the selected GitHub repositories.
- `Agents -> Settings` is resizable so the shared checklist can grow for longer repository or project lists.
- `Agents -> Settings` resizes the shared checklist to the visible window height so loaded repository and project rows appear immediately.
- Selecting an item in `Agents -> Review` runs `codex-core agents review run <pr>` using the configured review mode from `codex-core agents config`.
- In `Publish` mode, review findings are published immediately, using inline comments when possible and separate top-level PR comments otherwise.
- In `Pending` mode, review findings are created as one pending GitHub review, keeping inline comments as draft review comments and grouping non-inline findings into the draft review body.
- Review completion alerts include the persisted review job ID from `~/.codex/agents/reviews/<review-id>`.
- Review completion alerts include per-comment failure reasons when inline comment posting is skipped or rejected.
- Quit stops managed background processes, then terminates the Codex macOS app before app termination.
- CLI executable lookup is deterministic and only checks `/opt/homebrew/bin` and `/usr/local/bin`.
- Managed CLI subprocesses run with a deterministic environment that includes `/opt/homebrew/bin`, `/usr/local/bin`, and standard system paths.
- Profile management section is labeled `Profiles` and includes profile switch/remove actions plus `Add`.
- When profile listing fails transiently, the menu preserves the last loaded profile list so logged-out state can still show known profiles as unselected.
- Threads menu includes:
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
