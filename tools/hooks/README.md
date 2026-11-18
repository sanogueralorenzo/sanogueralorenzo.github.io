# Browser Hooks

Hooks for websites you are signed into. The [Slack hook](slack/README.md)
connects your keyword-prefixed messages to Codex, Claude, or another CLI and replies
as you in the same thread. Listening is automatic and invisible while the bridge
and a Slack tab are open. One Rust bridge and one extension background worker
serve all website adapters. Python handles setup and CLI adapters; Slack is the
available website adapter.

## Setup or update

1. Install Git, stable Rust/Cargo with a C compiler, Python 3.11+, Edge or Chrome,
   and Codex or Claude CLI on macOS or Linux. Sign in with `codex login` or
   `claude auth login`.
2. Run:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/tools/hooks/install.sh | sh
   ```

3. Run `browser-hooks start`. Open `edge://extensions` or `chrome://extensions`,
   enable **Developer mode**, select **Load unpacked**, and choose the printed
   extension folder. Allow its Slack and localhost access. Pairing is automatic;
   load or reload the extension within ten minutes of starting the bridge.
4. Open or reload Slack, then send `chat Reply with hello` or
   `claude Reply with hello` in your self-DM. Keep your computer awake and one Slack
   tab open to receive commands, including ones sent from your phone.

Setup builds only changed Rust sources, prepares the extension, and preserves
existing configuration, pairing and sessions. It leaves the bridge stopped and
removes the previous login service. Nothing starts at login or restarts after a
crash or reboot. Start the bridge explicitly whenever you want to use it.

To update, rerun the download installer or update your checkout and run
`browser-hooks setup`. Then run `browser-hooks start`, reload Browser Hooks on the
Extensions page, and reload Slack. From a local checkout, run
`python3 tools/hooks/cli.py setup` instead; add `--workspace /path/to/project` to
choose the initial workspace.

## Commands and files

```sh
browser-hooks setup   # install/configure; leave stopped
browser-hooks start   # start once in the background; safe to repeat
browser-hooks stop    # stop the bridge and interrupt active requests
browser-hooks status  # bridge, pairing, providers and last error
```

Closing the terminal after `start` does not stop the bridge. Use `stop` to turn it
off. Config changes take effect after `stop` followed by `start`. Accepted work,
unsent replies and session IDs survive a stop; interrupted turns need a follow-up.

The launcher is `~/.local/bin/browser-hooks`. Application files stay outside the
public checkout in `~/.local/share/browser-hooks`:

```text
browser-hooks/
├── bin/browser-hooks-bridge
├── bridge.pid, bridge.lock  # explicit process control
├── build/                  # Cargo cache and build log
├── extension/
├── pairing.json            # browser pairing credentials
├── logs/bridge.log
├── source/                 # download installer's managed checkout
└── hooks/slack/
    ├── config.json
    ├── sessions.lock
    └── sessions.sqlite3
```

Use `BROWSER_HOOKS_HOME` or `--home /absolute/path` for another application folder.
The temporary `extension/bridge-pairing.json` is deleted after pairing, after ten
minutes, or when the bridge stops. If pairing expires, run `browser-hooks stop`,
then `browser-hooks start`, then reload the extension. Hover over the popup dot
for details; run `browser-hooks status` for diagnostics.

Checks from the repository root:

```sh
cargo test --locked --manifest-path tools/hooks/bridge/Cargo.toml
python3 -m unittest discover -s tools/hooks/slack/tests
node --test tools/hooks/slack/*.test.mjs
```
