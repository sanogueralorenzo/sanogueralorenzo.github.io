# Slack browser listener

A keyword at the beginning of your own message triggers a configured command.
Works in public/private channels, DMs and group DMs you can access. Answers stay
in the thread; follow-ups with the keyword resume its agent session. Threads run
in parallel, with requests inside each thread processed in order.

**👀** queued/running · **✅** answered · **🤖** generated answer.

## Setup

Requires macOS/Linux, Python 3.11+, an authenticated coding CLI, and the
[Browser Hooks extension](../README.md). From this directory:

```sh
python3 bridge.py init --agent codex --keyword hook --workspace /path/to/project
python3 bridge.py serve
```

Open the extension popup, enter the pairing code printed by `serve`, and choose
**Pair local bridge**. Then send `hook your request` in Slack. Pairing persists
across restarts. The bridge must stay running for local agents; the browser
listener attaches automatically whenever Slack opens. No manual listening toggle.

On macOS, `python3 bridge.py install` runs the bridge at login instead of keeping
a terminal open. Stop a foreground `serve` first. Its pairing code and diagnostics
are in `~/.local/state/browser-hooks/slack/bridge.log`.

`init --agent claude` selects Claude instead. Configuration lives outside the
checkout at `~/.config/browser-hooks/slack.json`; edit it and restart the bridge.
Add keywords to `commands`, and map project aliases to directories in `projects`.
The first project alias in a request selects that workspace; follow-ups inherit it.

Each command has `start` and `resume` argument arrays, for example:

```json
{
  "start": ["python3", "/absolute/path/to/slack/agents/codex.py"],
  "resume": ["python3", "/absolute/path/to/slack/agents/codex.py", "{session_id}"]
}
```

Commands read the prompt from stdin and print one JSON object containing
`session_id` and `answer` (1–12,000 characters). No shell is involved. Codex and
Claude wrappers are included. Agents inherit your existing CLI permissions;
interactive approvals are not bypassed. Commands time out after 600 seconds;
`timeout_seconds` can lower that limit. Ctrl-C stops the bridge and its children.

Slack tokens/cookies never leave the Slack page. The extension sends message
context to a paired loopback bridge on port 19736. Pairing keys, deduplication,
and agent sessions live in `~/.local/state/browser-hooks/slack`, never this repo.
Only keyword requests and their thread context reach the local command.

For a browser-only check, choose **Echo test**, set a keyword, and save. It replies
without invoking a local command. Switch back to **Local agent** for normal use.

Reloads/reconnects do not replay missed messages. Agent sessions survive bridge
restarts, but interrupted commands and uncertain sends are never automatically
retried. Start a new keyword message to retry deliberately. Slack's browser API
and event protocol are unofficial and may change.
