# Slack browser hook

![Agent Slack banner](docs/banner.png)

Send `chat your request` for Codex or `claude your request` for Claude. Your own
keyword-prefixed messages trigger work in channels and DMs, including messages
sent from your phone. Replies appear as you in the same thread; follow-ups resume
the agent session. **👀** acknowledges receipt and stays on the request; the thread
reply gives the answer or explains the failure.

Follow [Browser Hooks setup](../README.md#install-or-update) to install the shared
extension and Rust bridge service. The popup shows Slack and a green/gray connection
dot. Listening runs automatically and invisibly; no toggle or on-page UI.
Messages, job results and connection status arrive as events, without idle
polling. Socket keepalives maintain the connections; failures reconnect automatically.

## Configure

Edit `~/.local/share/browser-hooks/hooks/slack/config.json`, then run
`browser-hooks install`. Initial setup detects installed CLIs and creates the
`chat` and/or `claude` keywords. Each key in `commands` is a trigger keyword.
Each command has `start` and `resume` argument arrays; only `resume` includes
`{session_id}`. Commands read the prompt from stdin and return JSON with
`session_id` and `answer`. Codex/Claude adapters are included; other CLIs can use
the same contract.

Set `workspace` for the default directory and `projects` for aliases mapped to
project directories. The first alias in a request selects the project; follow-ups
inherit it. Native CLI models and permissions are preserved. `timeout_seconds`
sets the per-command limit, up to 600 seconds.

## Troubleshoot

Run `browser-hooks slack status` to check the bridge, pairing, keywords and last
error. The installer builds the bridge; rerun it after updating Rust source.
Failed requests show an actionable message in their Slack thread and the
popup tooltip. For an expired login, run `codex login` or `claude auth login`,
then send a new request. Raw command output and credentials are never posted.

Slack's configuration and sessions live under `hooks/slack/` in the
[application folder](../README.md#commands-and-files). Browser pairing and service
logs are shared at the application level.
Authentication stays in the Slack page. Uncertain sends are never retried
automatically; messages missed while offline are not replayed. Slack's browser
authentication and event protocol are unofficial and may change.
