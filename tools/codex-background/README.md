# Codex Background

A Codex Mac app skill for dispatching work to a separate native task. It returns a task link immediately, leaving the originating task free.

## Install

From this repository root:

```sh
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
ln -s "$PWD/tools/codex-background" "${CODEX_HOME:-$HOME/.codex}/skills/codex-background"
```

The skill is available as `$codex-background` in the Mac app. It uses the app's `create_thread` tool. For pending worktree setup, `scripts/resolve_task.py` can find the real task ID later from a unique prompt marker.

## Return path limitation

The experimental `scripts/listener.py` can read saved child rollout files from byte offsets, track turns in SQLite, and queue progress and completion into the origin task. End-to-end tests showed that `codex queue` delivers once to the same task when it is idle or active. Each delivery is a **new user turn** that runs a model and may wait in the origin's queue. The skill therefore does not install or use the listener automatically.

[Codex App Server](https://learn.chatgpt.com/docs/app-server) documents `thread/inject_items` as adding model-visible history, not as posting a visible assistant update. A separate App Server cannot resume a Mac app task while the desktop owns its active writer. No supported passive same-conversation delivery path was verified. Agent remains available for its own live event stream until that gap is solved.

The experimental listener never writes directly to rollout files. Its tests cover complete-line parsing, restart offsets, worktree marker resolution, and queue reconciliation:

```sh
python3 -m unittest discover -s tools/codex-background/scripts -p 'test_*.py' -v
```
