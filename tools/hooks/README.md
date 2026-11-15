# Browser Hooks

Automatic hooks for websites you are already signed into. The
[Slack listener](slack/README.md) connects your own keyword-prefixed messages to
Codex, Claude, or another CLI and replies as you in their threads.

Follow [Slack installation](slack/README.md#install-or-update) for the guided
installer. For a local checkout, run `python3 tools/hooks/slack/bridge.py install`
from the repository root. Load this folder unpacked in Edge/Chrome and pair once
with the printed code. Listening is invisible and automatic; one tab per workspace listens.

Authentication stays in Slack. Permissions cover Slack, loopback communication,
and extension settings. After an update, reload the extension, then reload Slack.

Checks from the repository root:

```sh
node --test tools/hooks/slack/*.test.mjs
python3 -m unittest discover -s tools/hooks/slack/tests
```
