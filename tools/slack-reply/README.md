# Slack Reply

Local Slack Socket Mode bridge to the Codex, Claude, or Pi CLI. A message runs the selected provider only when its author is `SLACK_USER_ID` and its text contains `<@SLACK_USER_ID>`. Every answer is posted in the triggering message's thread, with one provider session per thread. A top-level trigger starts a fresh session using only that message, without channel history. Answers are posted with the authorized user's Slack token.

## Slack setup

1. Create a Slack app named **Slack Reply** with a bot user. Enable **Socket Mode** and create an app-level `xapp-` token with `connections:write`.
2. Enable **Event Subscriptions**. Subscribe to the bot events `message.channels`, `message.groups`, `message.im`, and `message.mpim` for the conversation types you want. Add the corresponding **bot token scopes** `channels:history`, `groups:history`, `im:history`, and `mpim:history`. Invite the bot to each channel it should listen to. You can omit unused conversation types and their scopes.
3. Under **User Token Scopes**, grant `chat:write` and the matching history scopes for threads you want to read: `channels:history`, `groups:history`, `im:history`, and/or `mpim:history`. Install or reinstall the app as the user whose messages should trigger it. Copy that user's `xoxp-` token and the app's `xoxb-` bot token. The app checks that the user token belongs to `SLACK_USER_ID` and that both tokens are for the same workspace.

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
# Edit .env with your tokens, Slack user ID, absolute workspace path, model, and effort.
./run.sh provider          # Show the selected provider (Codex by default).
./run.sh provider pi       # Or use "codex" or "claude"; fails if that CLI is absent.
./run.sh
```

`.env` is ignored by Git and `run.sh` requires mode `600`. Set `SLACK_REPLY_WORKSPACE` to the directory all CLIs should use, and grant the app only the Slack scopes you need. The selected provider, session map, and answer tracking live in `~/.local/state/slack-reply` by default, with private directory and file permissions; set `SLACK_REPLY_STATE_DIR` to change that path. Slack tokens are removed from every CLI subprocess environment. `CODEX_MODEL` and `CODEX_REASONING_EFFORT` configure Codex; optional `CLAUDE_MODEL`, `CLAUDE_REASONING_EFFORT`, `PI_MODEL`, and `PI_THINKING` override local CLI defaults. Codex uses a workspace-write sandbox and never-ask approval policy. Claude runs with `acceptEdits` permission mode; Pi uses its own tool settings. Authenticate each CLI separately. Pi uses [JSON events and saved sessions](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/json.md).

To trigger it, send a message from the configured user that explicitly mentions that same user. A reply to an existing Slack thread includes that thread through the triggering message and resumes its saved session on later self-mentions. A top-level message sends only itself, starts a thread with the answer, and saves the session for later self-mentions in that thread. Changing the provider affects new threads; existing threads stay with their original provider so their sessions remain resumable. Slack Reply ignores other users, bot messages, its own posted answers, and duplicate event deliveries. Stop it with Ctrl-C.
