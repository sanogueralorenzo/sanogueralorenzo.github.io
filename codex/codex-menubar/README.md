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
- Global shortcut `Control-Option-Z` opens a small `Run From Browser` panel regardless of Caps Lock state.
- Menu section labels are `Agents`, `Remote`, `Profiles`, and `Threads`.
- `Remote -> Start` enables remote auto-start for future app launches.
- `Remote -> Stop` disables remote auto-start for future app launches.
- `Agents -> Create` opens the same `Run From Browser` panel used by the global shortcut.
- `Agents` includes only `Create`, `View`, and `Settings`; task and review launch pickers are no longer shown in the menu.
- `Agents -> View` shows only persisted task and review runs.
- Task run rows use status prefixes: `·` in progress, `✓` completed, `X` failed.
- Review run rows use status prefixes: `·` in progress, `✓` published, `X` needs attention.
- `Agents -> View` exposes saved links only: task runs can open Jira and PR links, and review runs can open the PR link.
- The run panel reads the current tab URL directly from the frontmost supported browser without modifying the clipboard.
- Supported browsers for `Run From Browser` are Safari, Safari Technology Preview, Chrome, Arc, Brave, and Edge.
- When the current tab is a GitHub pull request, `Run From Browser` shows a `Review Mode` selector with `Publish` and `Pending` before running `codex-core agents review run <pr>`.
- When the current tab is a Jira ticket, `Run From Browser` shows `Spike` and `Task`; `Spike` runs `codex-core agents spike run <ticket>`, takes the existing Jira description and latest comments into account, and only posts back when it has materially new information. Posted spike comments are formatted as Jira ADF paragraphs and lists, while `Task` runs `codex-core agents task run <ticket>`.
- The menubar watches `~/.codex/agents/reviews` (or `CODEX_AGENTS_HOME/reviews`) so review status markers update from persisted job writes instead of timer polling.
- The menubar also watches `~/.codex/agents/tasks` (or `CODEX_AGENTS_HOME/tasks`) so task status markers update from persisted task job writes.
- `Agents -> Settings` only shows integration status for `gh` and `acli`.
- Selecting an item in `Agents -> Review` runs `codex-core agents review run <pr>` using the configured review mode from `codex-core agents config`.
- In `Publish` mode, review findings are published immediately, using inline comments when possible and separate top-level PR comments otherwise.
- In `Pending` mode, review findings are created as one pending GitHub review, keeping inline comments as draft review comments and grouping non-inline findings into the draft review body.
- Task, spike, and review success paths use macOS notifications instead of modal completion alerts.
- Review completion notifications include the persisted review job ID from `~/.codex/agents/reviews/<review-id>`.
- Review completion notifications include per-comment failure reasons when inline comment posting is skipped or rejected.
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
