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
- Menu includes `Open` as the first action; it launches Codex if needed or brings it to focus when already running.
- Quit stops managed background processes, then terminates the Codex macOS app before app termination.
- CLI executable lookup is deterministic and only checks `/opt/homebrew/bin` and `/usr/local/bin`.
- Threads actions: `Merge Threads`, `Remove Threads`.
- `Remove Threads` offers `All`, `1d`, `3d`, `7d` filters; default view is `All` active threads.
- Thread lists are sourced from `codex-sessions list` and sorted latest-updated first.
- Rate limits are fetched on-demand from `codex app-server` (`account/rateLimits/read`).
- Rate limits wait for the `account/rateLimits/read` JSON-RPC response (`id: 2`) before terminating the app-server process.

### Storage

- `/Applications/Codex Menu Bar.app`
- `~/Library/LaunchAgents/io.github.sanogueralorenzo.codex.menubar.plist`
- `/tmp/codex-menu-menubar.out.log`
- `/tmp/codex-menu-menubar.err.log`
