---
name: codex-background
description: Dispatch explicitly requested work to a separate native Codex Mac app task and return its task link. Use when the user asks for background work or invokes $codex-background.
---

# Background Codex work

Start the requested work in a new native Mac app task and return promptly. This skill does not promise automatic updates in the originating task: the available queue path creates follow-up user turns and runs a model for every update.

1. Write a self-contained child prompt with the user's objective, constraints, and authorization. Preserve their scope without copying unrelated conversation history. For a worktree task that may return only a pending client ID, record the Unix timestamp (`python3 -c 'import time; print(time.time())'`), create a token with `python3 "${CODEX_HOME:-$HOME/.codex}/skills/codex-background/scripts/resolve_task.py" new`, and append `[codex-background-id: TOKEN]` to the prompt. Tell the child not to repeat the marker.
2. Use the Codex app's `list_projects` and `create_thread` tools. Use the saved project's worktree environment for repository work when it is a Git repository, unless the user specified another environment. Use a projectless task when no project applies. Do not replace native dispatch with `codex exec`.
3. Give the user the real child task ID or pending client task marker. Include `::created-thread{threadId="CHILD_ID"}` or `::created-thread{clientThreadId="CLIENT_ID"}` on its own line for the Mac app task link. End this turn without waiting for the child.

If a worktree returns only `clientThreadId` and the real ID is needed later, run `python3 "${CODEX_HOME:-$HOME/.codex}/skills/codex-background/scripts/resolve_task.py" resolve TOKEN --since SECONDS`. Do not dispatch the same request again while setup is pending. Use the app's `wait_threads` or `read_thread` on demand when the user asks for status. Do not install the experimental listener or queue updates to the originating task unless the user explicitly accepts that those updates become model-running follow-up turns.
