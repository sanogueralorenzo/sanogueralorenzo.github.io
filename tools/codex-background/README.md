# Codex Background

A Codex Mac app skill that dispatches work to a native task and returns progress and completion to the originating task. Its small macOS LaunchAgent reads the child's `~/.codex/sessions/.../rollout-...-THREAD_ID.jsonl` file. It does not run a model while idle or modify rollout files.

## Install

From this repository root:

```sh
mkdir -p "${CODEX_HOME:-$HOME/.codex}/skills"
ln -s "$PWD/tools/codex-background" "${CODEX_HOME:-$HOME/.codex}/skills/codex-background"
python3 tools/codex-background/scripts/listener.py install
```

The skill is then available as `$codex-background` in the Mac app. The listener runs as `com.sanogueralorenzo.codex-background-listener` under the user's LaunchAgent domain. The skill's dispatch flow calls `install` again when needed; it leaves an already running, current listener in place.

## How it works

The skill uses the Mac app's `create_thread` tool. Each child prompt gets a unique dispatch marker. After dispatch, the skill registers the origin task ID and either the real child ID or a pending worktree marker. The listener resolves pending worktree setup from that marker, then follows the child rollout file from a saved byte offset. It stores the last turn ID and an outbox in SQLite at `~/.codex/background-listener/state.sqlite3`.

When the child emits commentary or `task_complete`, the listener calls the bundled `codex queue --thread SOURCE_ID --message ...`. That queue starts a model turn in the **same originating Mac app task** when it is idle, or places the update after its active turn. Ordinary idle periods cause no model calls. Progress updates are limited to one per minute per child; completion is sent immediately.

The listener records each complete JSONL line once, including after restart. It reconciles an interrupted queue attempt against user turns in the origin's rollout. If acceptance is ambiguous and no user turn is visible yet, it leaves the event marked `uncertain` and does not resend it automatically; this avoids duplicate updates. Inspect it with `python3 tools/codex-background/scripts/listener.py status TOKEN`.

## Check

```sh
python3 -m unittest discover -s tools/codex-background/scripts -p 'test_*.py' -v
```

The tests cover partial JSONL lines, saved offsets across restart, one delivery per event, pending worktree marker resolution, and ambiguous queue attempts.
