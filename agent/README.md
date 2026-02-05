# Agent

This folder is the home for a local automation stack around `opencode`.
It installs dependencies, defines reusable actions, and adds optional
adapters and schedules to run those actions.

## Quick start

1) Install system dependencies and the OpenCode web service:

```bash
./install.sh
```

2) After cloning a git repo, install repo guardrails:

```bash
./install-repo.sh
```

## Structure

- `actions/`: Reusable workflows that call `opencode` or adapters.
- `adapters/`: Integrations and wrappers (API calls, curl helpers).
- `jobs/`: Schedules and triggers (cron/systemd).
- `skills/`: Model-specific skills (Claude/GPT), reserved for later.
- `config/`: Local configuration (`.env`, not committed).
- `hooks/`: Git hook scripts installed by `install-repo.sh`.
- `docs/`: Notes and reference docs for this stack.

## Example flow

1) A job triggers an action at a scheduled time.
2) The action calls adapters to fetch data.
3) The action invokes `opencode` with a prompt and receives output.
4) The action optionally commits or pushes results based on conditions.
