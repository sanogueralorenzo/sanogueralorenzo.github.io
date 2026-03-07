## Intro

**Codex Menubar** is a macOS menu bar app that orchestrates local Codex CLIs.

## Quickstart

```shell
./scripts/install.sh
```

## Reference

- This module does not expose a standalone CLI help command.
- Integrates with:
  - `codex-auth` (required)
  - `codex-sessions` (required)
  - `codex-remote` (optional)
- Sessions submenu supports merge transfer (`source <- merger`) and stale hard-delete actions (1/3/7 days).

### Storage

- `/Applications/Codex Menu Bar.app`
- `~/Library/LaunchAgents/io.github.sanogueralorenzo.codex.menubar.plist`
- `/tmp/codex-menu-menubar.out.log`
- `/tmp/codex-menu-menubar.err.log`
