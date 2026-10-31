# Agent Slack

Run your local Codex or Claude CLI from Slack. Only messages from `SLACK_USER_ID` trigger work. Answers are posted in the same thread as that user, with a 🤖 reaction.

Requests receive 👀 immediately, including while queued. A successful reply replaces 👀 with ✅. A failure removes 👀 and logs the error locally; no error message is posted. Reactions require the `reactions:write` user scope.

## Setup

Requires Python 3.10+ and authenticated `codex` / `claude` executables on `PATH` for the providers you configure.

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
AGENT_SLACK_COMMANDS='{"chat":"codex","claude":"claude"}'
AGENT_SLACK_WORKSPACE=/absolute/path/to/default/workspace
AGENT_SLACK_PROJECTS='{"project":"/absolute/path/to/project","service":"/absolute/path/to/service"}'
```

Keywords are case-sensitive standalone words at the very start of a message, followed by a request. Every follow-up needs a keyword. There are no built-in keywords or fallback provider. Bot messages and duplicate deliveries do not trigger work.

For example, `chat investigate project` selects Codex in `project`; `claude review service` selects Claude in `service`. Aliases match complete words anywhere after the keyword, ignoring case. The first alias mentioned wins. The keyword is stripped before sending the current request; aliases stay in the text.

Each Slack thread has one current CLI session. Follow-ups retain its workspace unless an alias selects another. Switching provider or workspace starts a fresh session with the full thread context. Otherwise, resuming sends only messages newer than the previous request, skipping AI replies already known to that session. Other participants' messages supply context, not instructions.

Codex uses `codex exec --json` and `codex exec resume`; Claude uses `claude -p --output-format json` and `--resume`. Both read prompts from stdin and inherit their native configuration, including model, reasoning, and permissions. Replies use Slack Markdown, up to 12,000 characters.

Up to eight threads run concurrently; requests within a thread run in arrival order. Workspaces share filesystem access. Ctrl-C or SIGTERM stops CLI process groups and clears 👀 from cancelled requests.

Checks: `.venv/bin/python -m unittest discover -p 'test_*.py'`.
