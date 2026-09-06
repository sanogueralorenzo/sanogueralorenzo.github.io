# Palette

A small macOS clipboard menu. Copy something, find it by content or source app, and reuse it.

![Palette illustration](Palette.png)

*Generated illustration, not a runtime screenshot.*

- **⌥⇧V** opens or closes Palette. Escape or clicking away dismisses it.
- **⌘F** searches; **↑ / ↓** selects a clip.
- **Click** or **hover + ⌘C** copies an item. **⌘1–9** copies a numbered result.
- **Return** pastes into the previous app. Direct paste requires macOS Accessibility permission; copying does not.
- **Space** opens copied images and image files in macOS Quick Look. This interaction is under verification.

Supports text, links, PNG/TIFF images, files, and useful native rich text. Files remain at their original locations. **Clear History immediately removes all saved clips.** Quit stops capture; launching Palette starts it again.

Images retain their original data. Older history entries that only saved a thumbnail copy that smaller image.

History stays encrypted locally with a key in macOS Keychain. Defaults are 200 clips and 30 days; older pinned clips stay protected. Existing history and retention/exclusion settings in `~/Library/Application Support/Palette` remain usable. Private clipboard markers and obvious secrets are skipped, but detection is limited. Source apps are inferred from the foreground app, so background copies can be misattributed. Unreadable history is preserved and capture stops; failures appear in the menu-bar tooltip.

Quick Look temporarily writes the selected image privately. Palette removes its temporary file on close, Quit, or next launch; macOS manages its own preview cache.

## Build

Requires macOS 13+ and Xcode Command Line Tools. From this directory:

```sh
./build.sh
open build/Palette.app
```

Quit the installed app before replacing it. Use macOS Login Items to launch automatically.

For isolated manual review:

```sh
build/Palette.app/Contents/MacOS/PaletteHost --review --data-dir /tmp/palette-review
```

Review mode still observes the shared clipboard. Quit it when finished.
