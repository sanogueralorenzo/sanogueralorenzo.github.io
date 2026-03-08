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
- On app launch, menubar runs `codex-auth watch start`.
- Sessions submenu includes `watch-title` toggle (mapped to `codex-sessions watch-title start|stop|status`), merge transfer (`target <- merger`), and stale hard-delete actions (1/3/7 days).
- Merge Target/Merger pickers display conversation titles only (no session IDs).
- Remove stale sessions uses a compact dialog with 1d/3d/7d stale-window segmented control and folder-ordered multi-select deletion list.
- Stale-session rows are two-line: title + folder/updated/id metadata.
- Stale-session dialog includes `Select All` and `Clear` actions plus a dynamic `Delete N` primary button.
- Stale-session list supports click-to-toggle multi-select (no modifier key required), plus Cmd/Shift multi-select.
- Session ordering data comes from `codex-sessions list --folders` (CLI is source of truth).
- Stale session rows render folder + last updated + title from CLI list output.
- Stale session deletion executes one `codex-sessions delete --hard` call with all selected session IDs.

### Storage

- `/Applications/Codex Menu Bar.app`
- `~/Library/LaunchAgents/io.github.sanogueralorenzo.codex.menubar.plist`
- `/tmp/codex-menu-menubar.out.log`
- `/tmp/codex-menu-menubar.err.log`
