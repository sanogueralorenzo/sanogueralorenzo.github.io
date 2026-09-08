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

Select text, then **⌥R** opens Rewrite · **⌥1** Make shorter · **⌥2** Make clearer · **⌥3** Fix grammar. Click a style or use arrows and Return. The result replaces the selection; **⌘Z** undoes it where the source app supports Undo.

**Escape** or **⌥R** cancels. The pencil menu shows progress, errors, and Settings. If ⌥R is unavailable, open Rewrite from that menu.

Selected text goes to your chosen provider through Pi. Rewrite leaves the clipboard untouched and refuses changed selections or unsupported fields. Some browsers and custom editors cannot be rewritten. Check the result before using it.

Local development: `./build.sh` · Fast checks: `./tests/run.sh` · Menu and settings checks: `./tests/feedback.sh` (quit Rewrite first).
