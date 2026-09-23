---
name: codex-background
description: Dispatch explicitly requested work to a native Codex Mac app task and return progress and completion to the originating task through a persistent local listener. Use when the user asks for background work or invokes $codex-background.
---

# Background Codex work

Dispatch the user's work to a new native Mac app task. A local LaunchAgent reads the child's saved rollout file and queues an update to this originating task only when it sees progress or completion. This uses no scheduled model checks. Each queued update runs one model turn in the origin; it may wait behind a turn that is already active.

1. Read `CODEX_THREAD_ID` with `printenv CODEX_THREAD_ID`; it must be the originating task ID. If absent, do not promise updates here. Set `CODEX_BACKGROUND_SCRIPTS="${CODEX_HOME:-$HOME/.codex}/skills/codex-background/scripts"`. Run `python3 "$CODEX_BACKGROUND_SCRIPTS/listener.py" install` to ensure the persistent LaunchAgent is running.
2. Before dispatch, record the Unix timestamp (`python3 -c 'import time; print(time.time())'`) and create a marker with `python3 "$CODEX_BACKGROUND_SCRIPTS/resolve_task.py" new`. Write a self-contained child prompt with the user's objective, constraints, and authorization. Append `[codex-background-id: TOKEN]` and tell the child not to repeat the marker. Keep the marker unique to this dispatch.
3. Use the Codex app's `list_projects` and `create_thread` tools. Use the saved project's worktree environment for repository work when it is a Git repository, unless the user specified another environment. Use a projectless task when no project applies. Do not replace native dispatch with `codex exec`.
4. Register immediately: `python3 "$CODEX_BACKGROUND_SCRIPTS/listener.py" register --source SOURCE_ID --token TOKEN --label 'short task name' --since SECONDS --child CHILD_ID`. Omit `--child` when `create_thread` returned only `clientThreadId` during worktree setup. The listener resolves the real task ID from the unique marker in the new rollout file. If setup has no real task after 15 minutes, it queues a setup error to the origin. Do not dispatch a duplicate task.
5. Give the user the new task ID or pending client task marker and say updates will be queued here on meaningful progress and completion. Include `::created-thread{threadId="CHILD_ID"}` or `::created-thread{clientThreadId="CLIENT_ID"}` on its own line for the Mac app task link. End this turn promptly. Do not wait on the child, set up a heartbeat, or send it a follow-up through the origin task.

For diagnosis, run `python3 "$CODEX_BACKGROUND_SCRIPTS/listener.py" status TOKEN` and inspect `$HOME/.codex/background-listener/listener.err`. The listener stores byte offsets and turn IDs in SQLite; it never writes to rollout files. If registration or listener installation fails, report the error and the child task ID, and avoid promising automatic updates.
