# Codex Menu Bar

A macOS menu bar app that orchestrates Codex tools via local CLIs:
- `codex-auth`
- `codex-remote` (optional)

## Build

```bash
cd /path/to/codex-menubar
swift build
```

## Install .app

```bash
/path/to/codex-menubar/scripts/install.sh
```

The script always packages `release/Codex Menu Bar.app`, then installs to `/Applications`.
If installation fails, it prints:
`Drag /release/Codex Menu Bar.app to /Applications`

## Requirements

- `codex-auth` CLI must be installed in npm global `bin` (via `codex-auth/scripts/install.sh`).
- `codex-remote` CLI can be installed in npm global `bin` (via `codex-remote/scripts/install.sh`) to enable bot controls.

The app starts `codex-auth watch start` on launch so auth sync runs through CLI.
