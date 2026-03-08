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
- On app launch, menubar always runs `codex-sessions watch thread-titles start`.
- `Quit` performs best-effort stop for managed background processes (`codex-remote`, `codex-sessions` thread-title watcher, `codex-auth` watcher) before terminating the app.
- `Rate Limits` submenu is computed lazily on open (not during global menu refresh).
- Rate limits are fetched from `codex app-server` via `initialize` + `account/rateLimits/read` on demand.
- `Rate Limits` renders compact rows only: `5h <percent> <time>` and `Weekly <percent> <date>`.
- Threads submenu includes merge transfer (`target <- merger`) and stale hard-delete actions (1/3/7 days).
- Threads submenu actions are labeled `Merge Threads` and `Remove Threads`.
- Threads submenu is rendered as a compact list without divider lines between those actions.
- Merge Target/Merger pickers display conversation titles only (no thread IDs).
- Remove stale threads uses a compact dialog with 1d/3d/7d stale-window segmented control and multi-select deletion list.
- Stale-thread rows are two-line: title + folder/updated/id metadata.
- Stale-thread dialog includes `Select All` and `Clear` actions plus a dynamic `Delete N` primary button.
- Stale-thread list supports click-to-toggle multi-select (no modifier key required), plus Cmd/Shift multi-select.
- Thread ordering comes directly from `codex-sessions list --sort-by updated_at` (CLI source of truth, most recent first).
- Stale thread rows render folder + last updated + title from CLI list output.
- Stale thread deletion executes one `codex-sessions delete --hard` call with all selected thread IDs.

### Storage

- `/Applications/Codex Menu Bar.app`
- `~/Library/LaunchAgents/io.github.sanogueralorenzo.codex.menubar.plist`
- `/tmp/codex-menu-menubar.out.log`
- `/tmp/codex-menu-menubar.err.log`
