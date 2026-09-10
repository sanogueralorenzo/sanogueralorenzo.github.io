# Rewrite

![Rewrite — concise text from a minimal macOS menu](docs/Rewrite.png)

A small macOS menu for making selected text concise and clear, with grammar corrected. No chat or history.

**Install or update** from the latest `main` (macOS 14+ and Xcode Command Line Tools):

```sh
curl -fsSL https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/tools/rewrite/install.sh | sh
```

Installs in `~/Applications`. Install Pi separately, then run it and use `/login`:

```sh
npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest
pi
```

Choose **Provider → OpenAI** (default) or **Anthropic** in the pencil menu. Enable Rewrite in **System Settings → Privacy & Security → Accessibility**.

Select text and press **⌥R** to rewrite it. The result is copied to your clipboard; press **⌘V** to paste it.

**Escape** or **⌥R** cancels. The pencil dot disappears when the result is copied. The menu shows progress and errors. If ⌥R is unavailable, open Rewrite from that menu.

Selected text goes to your chosen provider through Pi. Rewrite reads the selected text without changing the source field. Some apps do not expose selected text to Accessibility. Check the result before using it.

Slack and other Electron apps are asked to enable their accessibility tree. Rewrite also reads text-marker selections, so highlighted Slack messages can be captured when the focused control has no standard selected-text value.

Local development: `./build.sh` · Core checks: `./tests/run.sh` (offline; selection capture, global shortcuts, and model quality untested).
