# Slack Reply

Local Slack Socket Mode bridge to the Codex, Claude, or Pi CLI. Only messages from `SLACK_USER_ID` starting with one of these lowercase words followed by whitespace can run a CLI:

| Prefix | Provider | Model | Reasoning |
| --- | --- | --- | --- |
| `bot` | `SLACK_REPLY_PROVIDER` | `SLACK_REPLY_MODEL`, or the CLI default | `SLACK_REPLY_REASONING_EFFORT`, or the CLI default |
| `chat` | Codex | `gpt-6.1-sol` | `high` |
| `claude` | Claude Code | `claude-opus-5-5` | `high` |

Leading whitespace, partial words, self-mentions, and keywords later in a message do not trigger it. Every follow-up needs a prefix. Answers are posted in the triggering thread with the authorized user's token, using Slack's native Markdown rendering (up to 12,000 characters).

Up to eight Slack threads run concurrently. Messages within each thread run in arrival order and resume its CLI session. Threads share filesystem access; use separate workspaces for simultaneous edits to the same project.

On macOS and Linux, Ctrl-C or SIGTERM stops CLI process groups, including child processes. Processes get two seconds to exit before being killed; queued requests do not start during shutdown.

## Slack setup

1. In [Slack apps](https://api.slack.com/apps), choose **Create New App → From a manifest**, select your workspace, and paste [manifest.yaml](manifest.yaml). It configures the bot user, Socket Mode, user message events, and OAuth scopes.
2. Under **Basic Information → App-Level Tokens**, create a token with `connections:write`. Copy its `xapp-` value to `SLACK_APP_TOKEN` in `.env`.
3. Under **OAuth & Permissions**, install the app as the user identified by `SLACK_USER_ID`. Copy the **User OAuth Token** (`xoxp-`) to `SLACK_USER_TOKEN` and **Bot User OAuth Token** (`xoxb-`) to `SLACK_BOT_TOKEN` in `.env`.

For an existing app, paste the manifest under **App Manifest** and reinstall if scopes change. User events cover the installing user's public/private channels, existing DMs, and group DMs. Remove unused conversation types and their matching history scopes from the manifest before importing. The bot scope supplies the bot token required by the current bridge; replies use the user token.

Slack [user tokens perform writes as the user](https://docs.slack.dev/authentication/tokens/). A bot token would post as the bot, so the user token is required. Your workspace must permit the requested user scopes. Missing conversation access or history scopes cause thread retrieval to fail; Slack Reply logs the Slack error and does not fall back to incomplete context. Slack's [`conversations.replies` limits](https://docs.slack.dev/reference/methods/conversations.replies/) may also affect large threads or some distributed apps.

## Run locally

Requires Python 3.10+ and an authenticated `codex`, `claude`, or `pi` CLI on your `PATH`.

```sh
cd tools/slack-reply
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
umask 077
cp .env.example .env
chmod 600 .env
# Edit .env with your tokens, Slack user ID, bot defaults, tier, and workspace paths.
./run.sh
```

`.env` is ignored by Git and `run.sh` requires mode `600`. Keep personal directory mappings there; commit only generic examples. State lives in `~/.local/state/slack-reply` with private permissions; `SLACK_REPLY_STATE_DIR` changes that path. Slack tokens are removed from CLI subprocess environments.

Set `SLACK_REPLY_PROVIDER` to `codex`, `claude`, or `pi` for `bot`. Optional `SLACK_REPLY_MODEL` and `SLACK_REPLY_REASONING_EFFORT` override that CLI's defaults. `chat` and `claude` always use the fixed profiles above, including resumed sessions. Each command selects its provider; changing provider or workspace starts a fresh session. Existing CLI sessions are resumed only when both match. Authenticate each CLI separately. Restart after editing `.env`.

Codex retains its normal sandbox and approval settings. Claude runs with `acceptEdits`; its explicit reasoning setting also overrides `CLAUDE_CODE_EFFORT_LEVEL` for that subprocess. Pi uses its own tool settings and [JSON events and saved sessions](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/json.md).

## Service tier

Set `SLACK_REPLY_TIER=default` (the default) or `SLACK_REPLY_TIER=fast` in `.env`, then restart. It applies to `SLACK_REPLY_PROVIDER`, including a fixed profile using that provider. Other providers retain their CLI tier defaults. Model and reasoning selections are unchanged.

| CLI | `fast` mapping |
| --- | --- |
| Codex | `service_tier="fast"` with the `fast_mode` feature enabled |
| Claude | `fastMode: true`; set `SLACK_REPLY_MODEL=opus` or a supported Opus model |
| Pi | Bundled extension sets OpenAI/Codex/xAI `service_tier: "priority"`, Google `serviceTier: "priority"`, or Anthropic `speed: "fast"` |

`default` explicitly disables these fast settings. Claude and Pi's Anthropic fast mode support Opus 5.5, Opus 5, and Opus 4.8; unsupported combinations fail without switching models. Pi rejects fast mode for other providers. Availability and pricing depend on the provider, model, and account. See [Codex speed](https://learn.chatgpt.com/docs/agent-configuration/speed) and [Claude fast mode](https://code.claude.com/docs/en/fast-mode).

## Commands and workspaces

`SLACK_REPLY_WORKSPACE` is the default directory. Define aliases in `SLACK_REPLY_PROJECTS` as a shell-quoted JSON object mapping lowercase names to existing directories:

```sh
SLACK_REPLY_PROJECTS='{"project":"/absolute/path/to/project","service":"/absolute/path/to/service"}'
```

Aliases match complete words anywhere after the prefix, ignoring case and preserving the request text. Partial words and hyphenated or underscored extensions do not match. When several aliases appear, the first one in the message selects the workspace, regardless of their order in `.env`.

- `bot explain this` uses the default provider and workspace.
- `chat investigate the failing tests in project` uses Codex / Sol / high in `project`.
- `claude review service` uses Claude / Opus 5.5 / high in `service`.
- `chat continue` in the same thread resumes its Codex session and workspace.

Without an alias, a follow-up keeps its saved workspace; a new thread uses `SLACK_REPLY_WORKSPACE`. Each thread has one current provider session. Switching provider or workspace starts fresh; switching back also starts fresh.

Commands inside an existing thread include the root and replies through the triggering message. Top-level commands send only their own request. Other participants' messages are context, not authorized instructions. Bot messages, posted answers, and duplicate event deliveries are ignored.

Checks: `python3 -m unittest discover -p 'test_*.py'` and `node --test test_pi_tier.mjs`.
