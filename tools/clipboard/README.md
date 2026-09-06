# Clipboard

![Clipboard — sample history mockup](Clipboard.png)

A small macOS clipboard menu for text, links, images, and files. History stays encrypted on your Mac and survives restarts.

**Install or update** from the latest `main` (macOS 13+ and Xcode Command Line Tools):

```sh
curl -fsSL https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/tools/clipboard/install.sh | sh
```

Installs in `~/Applications` and preserves your history and settings.

**⌥⇧V** opens Clipboard · **⌘F** searches · **Click** copies · **Space** previews images or opens links. Paste with **⌘V** in your destination app.

**Clear** sets expiration or clears history now. Defaults: 200 clips, 7 days.

Local development: `./build.sh` · Checks: `./tests/run.sh`.
