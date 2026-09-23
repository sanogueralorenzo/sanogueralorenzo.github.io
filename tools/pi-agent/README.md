# Pi Agent

Pi Agent turns a Pi terminal session into a background task dispatcher. Type a request normally: a coordinator assigns independent work to Pi worker, scout, or reviewer sessions. A local supervisor keeps them running after Pi closes. A reporter model writes short progress and completion updates into the Pi transcript when child events arrive.

## Start

Requires Pi 0.85.1, Node 22+, and working `openai-codex` authentication (`pi auth check --provider openai-codex`).

```bash
cd tools/pi-agent
npm install
pi install "$PWD"
pi
```

The package is installed by local path, so edits in this folder take effect on the next Pi launch. To try it for one session without installing, run `pi --extension "$PWD/extension.ts"` from this directory.

Typed messages go to the coordinator. The following commands remain available:

| Command | Purpose |
| --- | --- |
| `/agent-jobs` | Show task IDs and states. |
| `/agent-followup TASK_ID message` | Queue work in that child's saved Pi session. |
| `/agent-cancel TASK_ID` | Stop a child and clear its pending work. |
| `/agent-resume TASK_ID` | Retry a child interrupted before its output was ready. |
| `/agent-direct message` | Run a normal Pi turn in the current session. |

The default worker model is `openai-codex/gpt-5.6-sol`; routing and reporting use `openai-codex/gpt-5.6-luna`. Set `PI_AGENT_MODEL` and `PI_AGENT_UTILITY_MODEL` before the supervisor starts to choose other Pi model IDs.

## How it works

The supervisor stores private jobs, child sessions, byte offsets, and an event log in `~/.pi/agent-delegation`. It watches child JSONL output and invokes the reporter only for meaningful progress or completion. Pi displays summaries as transcript entries without starting a model turn. The event log is the durable record: Pi replays it after a restart, including when Pi has not written its own session file yet. A supervisor restart reconnects to running children and resumes from their saved offsets. Requests being routed are also recovered without creating duplicate jobs.

The feed is shared across Pi sessions on this machine, like Agent Home. Worker tasks keep their own persistent Pi context. One worker at a time may write in a given directory; read-only scouts and reviewers may run alongside it.

Agent's base, coordinator, router, and reporter instructions were migrated to `prompts/`. The role prompts make scouts and reviewers read-only. The former `read_history` instruction is unnecessary because Pi persists each child's conversation.

Images are handled by a normal Pi turn. This extension covers background text delegation and updates; it does not provide Agent's website or voice interface.

## Verify

```bash
npm run check
```

This checks types and runs an isolated supervisor integration test for dispatch, progress, ordered follow-ups, cancellation, restart recovery, and duplicate delivery. It does not change CI.
