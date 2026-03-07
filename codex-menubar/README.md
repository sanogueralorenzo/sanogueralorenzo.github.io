# Codex Menu Bar

A macOS menu bar app that orchestrates Codex tools via local CLIs:
- `codex-auth`
- `codex-remote` (optional)

## Build

```bash
cd /path/to/codex-menubar
swift build
```

## Package .app

```bash
/path/to/codex-menubar/scripts/package-menubar-app.sh
open "/path/to/codex-menubar/release/Codex Menu Bar.app"
```

## Requirements

- `codex-auth` CLI must be installed at `~/.local/bin/codex-auth` (for example via `codex-auth/scripts/install.sh`).
- `codex-remote` CLI can be installed at `~/.local/bin/codex-remote` (via `codex-remote/scripts/install.sh`) to enable bot controls.

The app starts `codex-auth watch start` on launch so auth sync runs through CLI.
