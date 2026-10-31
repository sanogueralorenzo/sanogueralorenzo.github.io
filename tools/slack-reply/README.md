# Slack Reply

Local Slack Socket Mode bridge to the Codex, Claude, or Pi CLI. Only messages from `SLACK_USER_ID` can trigger it. Map your own starting keywords to CLIs in `.env`; each CLI loads its native settings for the chosen workspace.

A keyword must be a separate word at the very start of your message, followed by whitespace and a request. Matching is case-sensitive. Leading whitespace, partial words, self-mentions, other people's messages, and keywords later in a message do not trigger it. Every follow-up needs a configured keyword. Answers are posted in the triggering thread with the authorized user's token, using Slack's native Markdown rendering (up to 12,000 characters).

Accepted requests receive an `:eyes:` reaction immediately, including while queued. After the reply is posted, the request's `:eyes:` is replaced by `:white_check_mark:`, and the AI reply receives `:robot_face:`. Reactions use the authorized user's token and require the `reactions:write` user scope. Reaction errors are logged without blocking replies.

Up to eight Slack threads run concurrently. Messages within each thread run in arrival order and resume its CLI session. Threads share filesystem access; use separate workspaces for simultaneous edits to the same project.

On macOS and Linux, Ctrl-C or SIGTERM stops CLI process groups, including child processes. Processes get two seconds to exit before being killed; queued requests do not start during shutdown.

## Slack setup

1. In [Slack apps](https://api.slack.com/apps), choose **Create New App → From a manifest**, select your workspace, and paste [manifest.yaml](manifest.yaml). It configures the bot user, Socket Mode, user message events, and OAuth scopes.
2. Under **Basic Information → App-Level Tokens**, create a token with `connections:write`. Copy its `xapp-` value to `SLACK_APP_TOKEN` in `.env`.
3. Under **OAuth & Permissions**, install the app as the user identified by `SLACK_USER_ID`. Copy the **User OAuth Token** (`xoxp-`) to `SLACK_USER_TOKEN` and **Bot User OAuth Token** (`xoxb-`) to `SLACK_BOT_TOKEN` in `.env`.

For an existing app, paste the manifest under **App Manifest** and reinstall if scopes change. User events cover the installing user's public/private channels, existing DMs, and group DMs. Remove unused conversation types and their matching history scopes from the manifest before importing. The bot scope supplies the bot token required by the current bridge; replies use the user token.

Slack [user tokens perform writes as the user](https://docs.slack.dev/authentication/tokens/). A bot token would post as the bot, so the user token is required. Your workspace must permit the requested user scopes. Missing conversation access or history scopes cause thread retrieval to fail; Slack Reply logs the Slack error and does not fall back to incomplete context. Slack's [`conversations.replies` limits](https://docs.slack.dev/reference/methods/conversations.replies/) may also affect large threads or some distributed apps.

## Run locally

Requires Python 3.10+. Install and authenticate each CLI used by your configured keywords (`codex`, `claude`, or `pi`) on your `PATH`.

```sh
cd tools/slack-reply
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
umask 077
cp .env.example .env
chmod 600 .env
# Edit .env with your tokens, Slack user ID, keyword commands, and workspace paths.
./run.sh
```

`.env` is ignored by Git and `run.sh` requires mode `600`. Keep personal directory mappings there; commit only generic examples. State lives in `~/.local/state/slack-reply` with private permissions; `SLACK_REPLY_STATE_DIR` changes that path. Slack tokens are removed from CLI subprocess environments.

## Keyword commands

`SLACK_REPLY_COMMANDS` is a shell-quoted JSON object mapping keywords to CLI names (`codex`, `claude`, or `pi`). There are no built-in commands or fallback provider.

```sh
SLACK_REPLY_COMMANDS='{"chat":"codex","claude":"claude"}'
```

These names are examples: rename them or add more keywords, including multiple keywords for the same CLI. Configured CLIs must be installed at startup; restart after editing `.env`.

Slack Reply adds only flags for noninteractive output, workspace selection, and session resumption. It does not override model, reasoning, tier, or permissions. Configure these in each CLI's own settings: `~/.codex/config.toml`, `~/.claude/settings.json`, or Pi's native settings. Workspace settings and inherited environment variables follow the CLI's normal precedence; resumed sessions follow its native resume behavior.

Launch commands are `codex exec --json -o <answer-file> --skip-git-repo-check -C <workspace> -`, `claude -p --output-format json`, and `pi --mode json -p`. Prompts go through stdin. Follow-ups use `codex exec resume`, Claude's `--resume`, or Pi's `--session` with the saved session ID.

## Commands and workspaces

`SLACK_REPLY_WORKSPACE` is the default directory. Define aliases in `SLACK_REPLY_PROJECTS` as a shell-quoted JSON object mapping lowercase names to existing directories:

```sh
SLACK_REPLY_PROJECTS='{"project":"/absolute/path/to/project","service":"/absolute/path/to/service"}'
```

Aliases match complete words anywhere after the prefix, ignoring case and preserving the request text. Partial words and hyphenated or underscored extensions do not match. When several aliases appear, the first one in the message selects the workspace, regardless of their order in `.env`.

- `chat explain this` uses the configured `chat` CLI and the default workspace.
- `chat investigate the failing tests in project` runs it in `project`.
- `claude review service` uses the configured `claude` CLI in `service`.
- `chat continue` in the same thread resumes its matching CLI session and workspace.

Without an alias, a follow-up keeps its saved workspace; a new thread uses `SLACK_REPLY_WORKSPACE`. Each thread has one current provider session. Switching provider or workspace starts fresh; switching back also starts fresh. Keywords using the same provider and workspace resume the same session.

Commands inside an existing thread include the root and replies through the triggering message. Top-level commands send only their own request. Other participants' messages are context, not authorized instructions. Bot messages, posted answers, and duplicate event deliveries are ignored.

Checks: `python3 -m unittest discover -p 'test_*.py'`.
