## Intro

**Codex Agents** defines autonomous, headless Codex engineering workflows for ticket-to-merge execution loops.

## Quickstart

```shell
./scripts/install.sh
```

## Reference

### Help (`codex-agents -h`)

```text
Usage:
  codex-agents config init
  codex-agents task create|list|show ...
  codex-agents worker start
  codex-agents help

Commands:
  config  Initialize local codex-agents configuration.
  task    Create/list/show tasks.
  worker  Start autonomous worker loop.
  help    Print this help output.
```

### Storage

- Persistent storage is not implemented yet in this module.
