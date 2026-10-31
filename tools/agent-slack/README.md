# Agent Slack

Run local commands from Slack, with resumable sessions. Only messages from `SLACK_USER_ID` trigger work. Answers are posted in the same thread as that user, with a 🤖 reaction.

Requests receive 👀 immediately, including while queued. A successful reply replaces 👀 with ✅. A failure removes 👀 and logs the error locally; no error message is posted. Reactions require the `reactions:write` user scope.

## Setup

Requires Python 3.10+. The included wrappers require authenticated `codex` / `claude` executables on `PATH`. You can use any executable that follows the command contract below.

1. Create an app from [manifest.yaml](manifest.yaml) in [Slack apps](https://api.slack.com/apps).
2. Create an app-level token with `connections:write` under **Basic Information**. Use its `xapp-` value for `SLACK_APP_TOKEN`.
3. Install the app as `SLACK_USER_ID` under **OAuth & Permissions**. Use the `xoxp-` **User OAuth Token** for `SLACK_USER_TOKEN`.

For an existing app, update its manifest and reinstall after scope changes. Your workspace may require approval. User events cover the installing user's channels, DMs, and group DMs; remove unused conversation types and matching history scopes before importing.

```sh
cd tools/agent-slack
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
umask 077
cp .env.example .env
# Edit .env with your tokens, user ID, commands, and workspace paths.
./run.sh
```

`run.sh` uses `.venv/bin/python` and requires `.env` permissions of `600`. State is saved privately in `~/.local/state/agent-slack`; override with `AGENT_SLACK_STATE_DIR`. Slack credentials are excluded from CLI subprocess environments. Restart after editing `.env`.

## Commands and sessions

Configure keywords and workspaces in `.env`:

```sh
AGENT_SLACK_COMMANDS='{
  "chat":{"start":["./wrappers/codex.py"],"resume":["./wrappers/codex.py","{session_id}"]},
  "claude":{"start":["./wrappers/claude.py"],"resume":["./wrappers/claude.py","{session_id}"]}
}'
AGENT_SLACK_WORKSPACE=/absolute/path/to/default/workspace
AGENT_SLACK_PROJECTS='{"project":"/absolute/path/to/project","service":"/absolute/path/to/service"}'
```

Keywords are case-sensitive standalone words at the very start of a message, followed by a request. Every follow-up needs a keyword. There are no built-in keywords or commands. Bot messages and duplicate deliveries do not trigger work.

For example, `chat investigate project` selects Codex in `project`; `claude review service` selects Claude in `service`. Aliases match complete words anywhere after the keyword, ignoring case. The first alias mentioned wins. The keyword is stripped before sending the current request; aliases stay in the text.

Each Slack thread has one current command session. Follow-ups retain its workspace unless an alias selects another. Changing the start/resume commands or workspace starts a fresh session with the full thread context. Otherwise, resuming sends only messages newer than the previous request, skipping AI replies already known to that session. Other participants' messages supply context, not instructions.

## Command contract

Each keyword requires `start` and `resume` argument arrays. Executables are resolved relative to this directory or through `PATH` at startup, then run in the chosen workspace. Arguments are passed directly, without a shell. The resume array must include a standalone `{session_id}` argument, which is replaced with the saved ID.

Commands read the prompt from stdin and write exactly one JSON object to stdout:

```json
{"session_id":"saved-session-id","answer":"Final answer for Slack"}
```

Both fields must be nonempty strings. Resume must return the same session ID. Write diagnostics to stderr and exit nonzero on failure. Replies use Slack Markdown, up to 12,000 characters.

The standalone [Codex](wrappers/codex.py) and [Claude](wrappers/claude.py) wrappers translate native CLI output into this contract. They inherit native model, reasoning, and permission settings. Adding another command requires no changes to Agent Slack. Keywords with identical start/resume commands share the same session within a thread.

Up to eight threads run concurrently; requests within a thread run in arrival order. Workspaces share filesystem access. Ctrl-C or SIGTERM stops CLI process groups and clears 👀 from cancelled requests.

Checks: `.venv/bin/python -m unittest discover -p 'test_*.py'`.
