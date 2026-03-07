## Intro

**Codex Agents** defines autonomous, headless Codex engineering workflows for ticket-to-merge execution loops.

## Quickstart

```shell
./scripts/install.sh
```

## Reference

### Help (`codex-agents help`)

```text
Usage:
  codex-agents help
  codex-agents config init
  codex-agents task create <TICKET-KEY>
  codex-agents task list
  codex-agents task show <TICKET-KEY>
  codex-agents worker start

Commands:
  config init         Initialize local codex-agents configuration.
  task create         Create a task from a ticket key.
  task list           List tracked tasks.
  task show           Show task details by ticket key.
  worker start        Start autonomous worker loop.
  help                Print this help output.
```

### Storage

- Persistent storage is not implemented yet in this module.
