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
- Quit stops managed background processes before app termination.
- Threads actions: `Merge Threads`, `Remove Threads`.
- Thread lists are sourced from `codex-sessions list` and sorted latest-updated first.
- Rate limits are fetched on-demand from `codex app-server` (`account/rateLimits/read`).

### Storage

- `/Applications/Codex Menu Bar.app`
- `~/Library/LaunchAgents/io.github.sanogueralorenzo.codex.menubar.plist`
- `/tmp/codex-menu-menubar.out.log`
- `/tmp/codex-menu-menubar.err.log`
