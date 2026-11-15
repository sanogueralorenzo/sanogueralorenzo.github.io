# Browser Hooks

Hooks that attach automatically to registered websites using the browser's
existing sign-in. The [Slack hook](slack/README.md) listens for keywords in your
own messages and replies as you, in the same thread.

## Install locally

1. On `edge://extensions` or `chrome://extensions`, enable **Developer mode**,
   choose **Load unpacked**, and select this folder.
2. Open or reload Slack. The listener attaches automatically; no Start button.
3. Set up the [local command bridge](slack/README.md) for Codex, Claude, or another
   command. For a browser-only check, choose **Echo test** in the extension popup.

After updating these files, reload the extension once, then reload Slack.
Allow access to Slack when Edge asks. One tab per workspace listens; other tabs
stand by and take over if it closes. Keep a Slack tab open and the computer awake.

Slack authentication stays in the page. Permissions cover Slack, local loopback
communication, and extension settings. No Slack app, OAuth approval, browser
profile extraction, Keychain access, or Browse installation is needed.

Checks from the repository root:

```sh
node --test tools/hooks/slack/*.test.mjs
python3 -m unittest discover -s tools/hooks/slack/tests
```
