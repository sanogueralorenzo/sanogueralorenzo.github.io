# Browser Hooks

Automatic hooks for websites you are signed into. The [Slack hook](slack/README.md)
connects your keyword-prefixed messages to Codex, Claude, or another CLI and replies
as you in the same thread. Listening is automatic and invisible. The resident
bridge runs in Rust; Python handles setup and the Codex/Claude adapters. One
background worker and one bridge process serve all website adapters, sharing
pairing and a single local event connection. Slack is the available adapter.

## Install or update

1. Install Git, stable Rust/Cargo with a C compiler, Python 3.11+, Edge or Chrome,
   and Codex or Claude CLI on macOS or Linux with systemd. Sign in with
   `codex login` or `claude auth login`.
2. Run:

   ```sh
   curl -fsSL https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/tools/hooks/install.sh | sh
   ```

3. Open `edge://extensions` or `chrome://extensions`, enable **Developer mode**,
   select **Load unpacked**, and choose the printed extension folder. Allow its
   Slack and localhost access. Pairing happens automatically; no code to copy.
4. Open or reload Slack, then send `chat Reply with hello` or
   `claude Reply with hello` in your self-DM. Keep your computer awake and one Slack
   tab open. No Slack app or workspace approval is required.

The installer builds the Rust bridge locally with SQLite included and starts it
automatically at login.

To update code, rerun the download installer or update your source checkout, then
run `browser-hooks install`. Reload Browser Hooks on the Extensions page, then
reload Slack. Configuration and sessions are preserved.

From a local checkout, run `python3 tools/hooks/cli.py install` instead. Add
`--workspace /path/to/project` to choose the initial workspace.

## Commands and files

```sh
browser-hooks install
browser-hooks status
browser-hooks slack status
browser-hooks serve          # foreground; stop the login service first
```

The launcher lives at `~/.local/bin/browser-hooks`. All application files live in
`~/.local/share/browser-hooks`, outside the public checkout:

```text
browser-hooks/
├── bin/browser-hooks-bridge # shared Rust executable
├── build/                  # Cargo build cache and build log
├── extension/
├── pairing.json            # shared browser credentials
├── logs/bridge.log          # shared service log
├── source/                 # download installer's managed checkout
└── hooks/
    └── slack/
        ├── config.json
        └── sessions.sqlite3
```

Use `BROWSER_HOOKS_HOME` or `--home /absolute/path` to choose another application
folder. The temporary pairing file in `extension/` is deleted after pairing,
after ten minutes, or when the bridge stops. If pairing expires, rerun
`browser-hooks install`, then reload the extension. Hover over the popup's
connection dot for details; run `browser-hooks slack status` for diagnostics.

Checks from the repository root:

```sh
cargo test --locked --manifest-path tools/hooks/bridge/Cargo.toml
python3 -m unittest discover -s tools/hooks/slack/tests
node --test tools/hooks/slack/*.test.mjs
```
