## Intro

**Codex Menubar** is a macOS menu bar app that orchestrates local Codex CLIs.

## Quickstart

```shell
./scripts/install.sh
```

- Installer behavior: stops any running `CodexMenuBar` process before replacing `/Applications/Codex Menu Bar.app`, then relaunches.

## Reference

- This module does not expose a standalone CLI help command.
- Integrates with:
  - `codex-auth` (required)
  - `codex-sessions` (required)
  - `codex-remote` (optional)
- Sessions submenu supports merge transfer (`target <- merger`) and stale hard-delete actions (1/3/7 days).
- Remove stale sessions uses a dialog with 1/3/7-day quick dropdown and folder-ordered multi-select deletion list.
- Session ordering data comes from `codex-sessions list --folders` (CLI is source of truth).
- Stale session rows render folder + last updated + title from CLI list output.
- Stale session deletion executes one `codex-sessions delete-many --hard` call with all selected session IDs.

### Storage

- `/Applications/Codex Menu Bar.app`
- `~/Library/LaunchAgents/io.github.sanogueralorenzo.codex.menubar.plist`
- `/tmp/codex-menu-menubar.out.log`
- `/tmp/codex-menu-menubar.err.log`
