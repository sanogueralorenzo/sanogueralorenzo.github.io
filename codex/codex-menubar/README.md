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
- Launch starts `codex-remote start --plain` only when remote auto-start has been enabled by a prior successful `Remote -> Start`.
- Launch agent executable path is fixed to `/Applications/Codex Menu Bar.app`.
- Install stops the loaded LaunchAgent first, replaces the app bundle, then bootstraps the LaunchAgent again so relaunch stays single-instance and auto-start remains configured.
- Menu includes `Open` as the first action; it launches Codex if needed or brings it to focus when already running.
- Status bar item uses the text `CA`.
- Menu section labels are `Remote` and `Profiles`.
- `Remote -> Start` enables remote auto-start for future app launches.
- `Remote -> Stop` disables remote auto-start for future app launches.
- Quit stops managed background processes, then terminates the Codex macOS app before app termination.
- CLI executable lookup is deterministic and only checks `/opt/homebrew/bin` and `/usr/local/bin`.
- Managed CLI subprocesses run with a deterministic environment that includes `/opt/homebrew/bin`, `/usr/local/bin`, and standard system paths.
- Profile management section is labeled `Profiles` and includes profile switch/remove actions plus `Add`.
- When profile listing fails transiently, the menu preserves the last loaded profile list so logged-out state can still show known profiles as unselected.

### Storage

- `/Applications/Codex Menu Bar.app`
- `~/Library/LaunchAgents/io.github.sanogueralorenzo.codex.menubar.plist`
- `/tmp/codex-menu-menubar.out.log`
- `/tmp/codex-menu-menubar.err.log`
