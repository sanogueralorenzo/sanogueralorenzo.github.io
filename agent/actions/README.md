# Actions

Actions are preset workflows that combine adapters and `opencode` prompts.
Each action should be small, composable, and easy to run by itself or via
`jobs/` schedules.

## Suggested layout

```
actions/
  summarize-repo/
    run.sh
    README.md
```

## Example action

`actions/summarize-repo/run.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

REPO_PATH="${1:-$PWD}"

opencode <<'EOF'
Summarize the changes in the last 7 days for this repo.
Focus on key decisions and next steps.
EOF
```

## Conventions

- Accept inputs via arguments and environment variables.
- Keep output deterministic and easy to parse.
- Prefer adapters for external API calls.
