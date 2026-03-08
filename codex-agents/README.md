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

### Help Patterns

```shell
codex-agents --help
codex-agents help task
codex-agents task --help
codex-agents task create --help
```

- Subcommand help output uses a shared usage/description formatter to keep text consistent.

### Storage

- Persistent storage is not implemented yet in this module.
