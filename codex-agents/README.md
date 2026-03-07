# codex-agents

`codex-agents` is a CLI for running autonomous, headless Codex agents that execute end-to-end engineering tasks with skills and your existing toolchain.

A typical workflow:

1. Agent reads Jira ticket `X` through `acli`.
2. Agent implements the ticket.
3. Agent opens a pull request using `gh`.
4. Agent waits for GitHub pings on that PR and applies review feedback in as many iterations as needed.
5. When the PR is pinged with `merge`, agent merges it.
6. After merge, agent transitions the Jira ticket to Dev Done.
7. Agent posts a Jira comment with affected areas and delivery notes.

## Initial CLI shape (proposal)

```bash
# Configure tool paths and defaults
codex-agents config init
codex-agents config set jira.project TS
codex-agents config set jira.done-transition "Dev Done"

# Create an autonomous task from a Jira ticket
codex-agents task create TS-1234

# Start a worker loop that listens for GitHub/Jira triggers
codex-agents worker start

# Inspect running and recent tasks
codex-agents task list
codex-agents task show TS-1234

# Trigger common actions manually (useful for testing)
codex-agents task review TS-1234
codex-agents task apply-feedback TS-1234
codex-agents task merge TS-1234

# Stop or clean up
codex-agents worker stop
codex-agents task cancel TS-1234
```

## External CLIs expected

- `codex`
- `acli`
- `gh`
