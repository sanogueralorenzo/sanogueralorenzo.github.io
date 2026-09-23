# Pi Agent

Pi Agent delegates requests from a Pi terminal session to child Pi tasks. A coordinator chooses worker, scout, or reviewer roles. A reporter model turns meaningful child progress and completion into short updates in the current Pi transcript. The extension runs only while that Pi session is open.

## Start

Requires Pi 0.85.1, Node 22+, and working `openai-codex` authentication (`pi auth check --provider openai-codex`).

```bash
cd tools/pi-agent
npm install
pi install "$PWD"
pi
```

The package is installed by local path, so edits take effect on the next Pi launch. To try it for one session without installing, run `pi --extension "$PWD/extension.ts"` from this directory.

Typed text requests go to the coordinator. Images are handled by the normal Pi session. Commands:

| Command | Purpose |
| --- | --- |
| `/agent-jobs` | Show task IDs and states in this Pi session. |
| `/agent-followup TASK_ID message` | Queue a follow-up for that child after its current turn. |
| `/agent-cancel TASK_ID` | Stop a child and clear its pending work. |
| `/agent-direct message` | Run a normal Pi turn in the current session. |

The worker model defaults to `openai-codex/gpt-5.6-sol`; routing and reporting use `openai-codex/gpt-5.6-luna`. Set `PI_AGENT_MODEL` and `PI_AGENT_UTILITY_MODEL` before starting Pi to choose other model IDs.

## How it works

The extension owns the coordinator, worker, scout, reviewer, and reporter subprocesses directly. It reads each child process's JSON event stream, calls the reporter for meaningful progress or completion, and appends the update to the Pi transcript. It runs at most four child tasks at once and only one writing worker per directory. Read-only roles use Pi's read-only tool allowlist.

Tasks and follow-up queues live in memory. A normal Pi close or session switch stops active subprocesses and drops pending work; there is no daemon, event log, automatic replay, or restart recovery. Completed child turns use Pi's normal session files, so you can inspect or manually continue them later with Pi's `--session-id TASK_ID`. Work stopped before Pi saved a child turn may have no recoverable session. Transcript updates may also be lost if Pi closes before its own session is saved.

Agent's base, coordinator, worker, scout, reviewer, and reporter instructions are preserved in `prompts/`. `original-agent-instructions.md` is retained as the source reference. This extension covers background text delegation and updates, not Agent's website or voice interface.

## Static check

```bash
npm run check
```

This checks TypeScript types only. No test suite or non-site CI is included.
