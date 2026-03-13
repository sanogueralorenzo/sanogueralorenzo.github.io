## Intro

**Codex Menubar** is a macOS menu bar app that orchestrates local Codex tooling.

## Quickstart

```shell
./scripts/install.sh
```

## Reference

### Integrations

- Required: `codex-auth`, `codex-sessions`
- Optional: `codex-remote`

### Runtime Behavior

- Launch starts `codex-auth watch start`.
- Launch starts `codex-sessions watch thread-titles start`.
- Launch starts background auto-remove runs only when a day+mode selection is configured.
- Launch agent executable path prefers `/Applications/Codex Menu Bar.app` when available.
- Launch and install both clean up legacy `io.github.sanogueralorenzo.codexauth.menubar` startup entries.
- Menu includes `Codex` as the first action; it launches Codex if needed or brings it to focus when already running.
- Menu section labels are `Agents`, `Remote`, `Profiles`, and `Threads`.
- `Agents` includes a `View` submenu that combines running + recent tasks.
- In `Agents -> View`, recent task labels are prefixed by status: `•` in progress, `✓` completed, `X` failed.
- Quit stops managed background processes, then terminates the Codex macOS app before app termination.
- CLI executable lookup is deterministic and only checks `/opt/homebrew/bin` and `/usr/local/bin`.
- Profile management section is labeled `Profiles` and includes profile switch/remove actions plus `Add`.
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
