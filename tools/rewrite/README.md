# Rewrite

A small macOS menu for making selected text shorter, clearer, or grammatically correct. No chat or history.

**Install or update** from the latest `main` (macOS 14+ and Xcode Command Line Tools):

```sh
curl -fsSL https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/tools/rewrite/install.sh | sh
```

Installs in `~/Applications`. Install Pi separately, then run it and use `/login`:

```sh
npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest
pi
```

Choose **OpenAI** or **Anthropic** in Rewrite Settings. OpenAI uses Luna with reasoning off and priority requested; Anthropic uses Haiku with thinking off. Enable Rewrite in **System Settings → Privacy & Security → Accessibility**.

Select text, then **⌥R** opens Rewrite · **⌥1** Make shorter · **⌥2** Make clearer · **⌥3** Fix grammar. Click a style or use arrows and Return. The result is copied to your clipboard; press **⌘V** to paste it.

**Escape** or **⌥R** cancels. The pencil dot disappears when the result is copied. The menu shows progress, errors, and Settings. If ⌥R is unavailable, open Rewrite from that menu.

Selected text goes to your chosen provider through Pi. Rewrite reads the selected text without changing the source field. Some apps do not expose selected text to Accessibility. Check the result before using it.

Local development: `./build.sh` · Core checks: `./tests/run.sh` (offline; native UI and model quality untested).
