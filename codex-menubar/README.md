## Intro

**Codex Menubar** is a macOS menu bar app that orchestrates local Codex tooling.

## Quickstart

```shell
./scripts/install.sh
```

## Reference

### Integrations

- Required: `codex-auth`, `codex-app-server`
- Optional: `codex-remote`

### Runtime Behavior

- Launch starts `codex-auth watch start`.
- Launch starts `codex-app-server sessions watch thread-titles start`.
- Launch starts `codex-remote start --plain` only when remote auto-start has been enabled by a prior successful `Remote -> Start`.
- Launch starts background auto-remove runs only when a day+mode selection is configured.
- Launch agent executable path is fixed to `/Applications/Codex Menu Bar.app`.
- Menu includes `Codex` as the first action; it launches Codex if needed or brings it to focus when already running.
- Menu section labels are `Agents`, `Remote`, `Profiles`, and `Threads`.
- `Remote -> Start` enables remote auto-start for future app launches.
- `Remote -> Stop` disables remote auto-start for future app launches.
- `Agents` includes a `View` submenu that combines running + recent tasks.
- In `Agents -> View`, recent task labels are prefixed by status: `•` in progress, `✓` completed, `X` failed.
- Quit stops managed background processes, then terminates the Codex macOS app before app termination.
- CLI executable lookup is deterministic and only checks `/opt/homebrew/bin` and `/usr/local/bin`.
- Managed CLI subprocesses run with a deterministic environment that includes `/opt/homebrew/bin`, `/usr/local/bin`, and standard system paths.
- Profile management section is labeled `Profiles` and includes profile switch/remove actions plus `Add`.
- When profile listing fails transiently, the menu preserves the last loaded profile list so logged-out state can still show known profiles as unselected.
- Threads menu includes:
  - `Auto-Remove` title row clears the saved day+mode selection (disables auto-remove).
  - `Auto-Remove` window: `1 day`, `3 days`, `7 days` (single-select checkmark)
  - Each day option has a submenu with `Archive` and `Delete`.
- Selecting a day+mode persists immediately and restarts auto-remove runs.

### Storage

- `/Applications/Codex Menu Bar.app`
- `~/Library/LaunchAgents/io.github.sanogueralorenzo.codex.menubar.plist`
- `/tmp/codex-menu-menubar.out.log`
- `/tmp/codex-menu-menubar.err.log`
