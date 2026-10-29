# Slack Reply

Local Slack Socket Mode bridge to the Codex, Claude, or Pi CLI. A message runs the selected provider only when its author is `SLACK_USER_ID` and its text contains `<@SLACK_USER_ID>`. Every answer is posted in the triggering message's thread, with one provider session per thread. A top-level trigger starts a fresh session using only that message, without channel history. Answers are posted with the authorized user's Slack token using Slack's native Markdown rendering (up to 12,000 characters).

## Slack setup

1. Create a Slack app named **Slack Reply** with a bot user. Enable **Socket Mode** and create an app-level `xapp-` token with `connections:write`.
2. Enable **Event Subscriptions**. Under **Subscribe to events on behalf of users**, add `message.channels`, `message.groups`, `message.im`, and `message.mpim` for the conversation types you want. These require the corresponding **user token scopes** `channels:history`, `groups:history`, `im:history`, and `mpim:history`. Save Changes. User events cover conversations the installing user belongs to, including existing DMs; bot events only cover conversations the bot belongs to. You can omit unused conversation types and their scopes.
3. Under **User Token Scopes**, also grant `chat:write`. Install or reinstall the app as the user whose messages should trigger it when adding scopes. If the installed user token already has all required scopes, saving the event subscriptions is sufficient. Copy that user's `xoxp-` token and the app's `xoxb-` bot token. The app checks that the user token belongs to `SLACK_USER_ID` and that both tokens are for the same workspace.

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
# Edit .env with your tokens, Slack user ID, provider, model, and absolute workspace path.
./run.sh
```

`.env` is ignored by Git and `run.sh` requires mode `600`. Set `SLACK_REPLY_WORKSPACE` to the directory all CLIs should use, and grant the app only the Slack scopes you need. The session map and answer tracking live in `~/.local/state/slack-reply` by default, with private directory and file permissions; set `SLACK_REPLY_STATE_DIR` to change that path. Slack tokens are removed from every CLI subprocess environment. Set `SLACK_REPLY_PROVIDER` to `codex`, `claude`, or `pi` in `.env`. Optional `SLACK_REPLY_MODEL` and `SLACK_REPLY_REASONING_EFFORT` override the selected provider's CLI defaults. Use a model identifier and reasoning level supported by that provider; the adapters pass them as Codex model/config, Claude model/effort, or Pi model/thinking flags. Codex keeps its normal sandbox and approval settings. Restart after editing `.env`; provider changes apply to new threads, while existing threads keep their original provider. Model and reasoning overrides apply on each invocation for the selected provider, including resumed sessions. Threads pinned to another provider use that CLI's session and defaults without receiving the selected provider's overrides. Claude runs with `acceptEdits` permission mode; Pi uses its own tool settings. Authenticate each CLI separately. Pi uses [JSON events and saved sessions](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/json.md).

To trigger it, send a message from the configured user that explicitly mentions that same user. A reply to an existing Slack thread includes that thread through the triggering message and resumes its saved session on later self-mentions. A top-level message sends only itself, starts a thread with the answer, and saves the session for later self-mentions in that thread. Slack Reply ignores other users, bot messages, its own posted answers, and duplicate event deliveries. Stop it with Ctrl-C.
