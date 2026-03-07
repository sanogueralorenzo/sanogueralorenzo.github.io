## Intro

**Codex Agents** defines autonomous, headless Codex engineering workflows for ticket-to-merge execution loops.

## Quickstart

### Prepare required local tools

```shell
../install.sh
```

## Reference

- Current status: workflow + CLI surface definition module.
- External CLIs expected: `codex`, `acli`, `gh`.
- Proposed command surface:

```shell
codex-agents config init
codex-agents task create <TICKET-KEY>
codex-agents worker start
codex-agents task list
codex-agents task show <TICKET-KEY>
```
