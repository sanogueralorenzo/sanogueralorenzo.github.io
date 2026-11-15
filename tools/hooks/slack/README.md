# Slack browser listener

Send `chat your request` for Codex or `claude your request` for Claude. Your own
keyword-prefixed messages trigger work in channels and DMs, including messages
sent from your phone. Replies appear as you in the same thread; follow-ups resume
the agent session. **👀** queued/running · **✅** answered · **⚠️** failed.

## Install or update

Requires macOS or Linux with systemd, Git, Python 3.11+, and a signed-in coding CLI.

```sh
curl -fsSL https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/tools/hooks/slack/install.sh | sh
```

The installer detects installed CLIs, creates the default keywords, starts the
background service, and prints the extension folder and pairing code. Load that
folder unpacked in Edge/Chrome, then enter the code in **Browser Hooks**. No Slack
app or workspace approval. Slack attaches automatically whenever it opens.

Rerun the command to update. Configuration and sessions are preserved. Reload the
extension once after updates, then reload Slack. Keep a Slack tab open and the
computer awake. From a local checkout, `python3 tools/hooks/slack/bridge.py install`
performs setup without downloading another copy. Use `--workspace /path/to/project`
to choose the default workspace on first installation.

## Configure

Edit `~/.config/browser-hooks/slack.json`, then rerun the installer or run
`slack-hook install`. Each key in `commands` is a trigger keyword. Each command
has `start` and `resume` argument arrays; only `resume` includes `{session_id}`.
Commands read the prompt from stdin and return JSON with `session_id` and `answer`.
Codex/Claude adapters are included; other CLIs can use the same contract.

Set `workspace` for the default directory and `projects` for aliases mapped to
project directories. The first alias in a request selects the project; follow-ups
inherit it. Native CLI models and permissions are preserved. `timeout_seconds`
sets the per-command limit, up to 600 seconds.

## Troubleshoot

Run `slack-hook status` to check the bridge, pairing, keywords and last error.
Failed requests show an actionable message in their Slack thread and the popup.
For an expired login, run `codex login` or `claude auth login` on your computer,
then send a new request. Raw command output and credentials are never posted.

State and private logs live in `~/.local/state/browser-hooks/slack`. Pairing codes
last ten minutes; rerun the installer for a fresh code. Uncertain sends are never
retried automatically. Messages missed while offline are not replayed. Slack's
browser authentication and event protocol are unofficial and may change.
