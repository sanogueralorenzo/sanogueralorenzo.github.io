# Slack browser listener

![Agent Slack banner](docs/banner.png)

Send `chat your request` for Codex or `claude your request` for Claude. Your own
keyword-prefixed messages trigger work in channels and DMs, including messages
sent from your phone. Replies appear as you in the same thread; follow-ups resume
the agent session. **👀** queued/running · **✅** answered · **⚠️** failed.

## Install or update

1. **Install the prerequisites:** macOS or Linux with systemd, Git, Python 3.11+,
   Edge or Chrome, and Codex or Claude CLI.

2. **Sign in to your coding CLI:** run `codex login` or `claude auth login` on
   your computer.

3. **Run the installer:**

    ```sh
    curl -fsSL https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/tools/hooks/slack/install.sh | sh
    ```

   It detects installed CLIs, creates the `chat` and/or `claude` keywords, starts
   the background service, and prints an extension folder and pairing code.

4. **Load the extension:** open `edge://extensions` or `chrome://extensions`,
   enable **Developer mode**, select **Load unpacked**, and choose the printed
   extension folder. Allow its Slack and localhost access.

5. **Pair once:** open **Browser Hooks** from the browser's Extensions menu,
   paste the printed code into the Slack row, and press **Enter**. Its dot turns
   green when Slack is connected; gray means disconnected. Hover for details.

6. **Open Slack and test:** sign in, or reload an existing Slack tab, then send
   `chat Reply with hello` or `claude Reply with hello` in your self-DM.
   The answer appears as you in that message's thread.

Listening runs automatically and invisibly; nothing is added to the Slack page.
Pairing authorizes the extension to use your local command bridge and persists
across restarts. Open the extension only for pairing or troubleshooting. Keep your
computer awake and one Slack tab open. Messages sent from your phone can trigger
the same listener.
No Slack app or workspace approval is required.

**To update**, rerun the installer, reload Browser Hooks on the Extensions page,
then reload Slack. Configuration and sessions are preserved.

From a local checkout, `python3 tools/hooks/slack/bridge.py install` performs setup
without downloading another copy. Use `--workspace /path/to/project` to choose
the default workspace on first installation.

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
