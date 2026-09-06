# Clipboard

A small macOS clipboard menu. Copy something, find it by content or source app, and reuse it.

![Clipboard illustration](Clipboard.png)

*Generated illustration, not a runtime screenshot.*

- **⌥⇧V** opens or closes Clipboard. Escape or clicking away dismisses it.
- **⌘F** searches; **↑ / ↓** selects a clip.
- **Click** or **hover + ⌘C** copies an item. **⌘1–9** copies a numbered result.
- **Return** copies the selected clip, closes Clipboard, and sends ⌘V to the app you were using. This automatic paste requires macOS Accessibility permission; clicking to copy and pasting yourself does not.
- **Space** previews copied images and image files in macOS Quick Look, or opens links in your default browser. Image rows show “Space to Preview” on hover; links show “Space to Open”. Other rows have no hover hint. Quick Look interaction is under verification.

Supports text, links, PNG/TIFF images, files, and useful native rich text. Files remain at their original locations. **Clear → Now immediately removes all saved clips.** Clear is always available; Now is disabled when history is empty. The timed options remove each clip once it reaches 30 minutes, 8 hours, or 7 days old; 7 days is selected by default. Expiry is checked every minute while running and when the app or menu opens. Quit stops capture; launching Clipboard starts it again.

Images retain their original data for copying and Quick Look; thumbnails are only used in the menu. Older history entries that only saved a thumbnail must be copied again from the original source before they can be reused or previewed.

History stays encrypted locally in `~/Library/Application Support/Clipboard`, with a key in macOS Keychain. Defaults are 200 clips and 7 days. Private clipboard markers and obvious secrets are skipped, but detection is limited. Source apps are inferred from the foreground app, so background copies can be misattributed. Unreadable history is preserved and capture stops; failures appear in the menu-bar tooltip.

New copies replace the oldest entries when history reaches 200 clips or 64 MiB of serialized data (before encryption). A copy can evict several older entries to fit. Individual copies above 8 MiB of native data and images above the image dimension limits (40 megapixels or 16,000 pixels per side) are skipped.

Quick Look temporarily writes the selected image privately. Clipboard removes its temporary file on close, Quit, or next launch; macOS manages its own preview cache.

## Build

Requires macOS 13+ and Xcode Command Line Tools. From this directory:

```sh
./build.sh
open build/Clipboard.app
```

Quit the installed app before replacing it. Clipboard registers to launch at login on its first normal launch. You can disable this in System Settings → General → Login Items; Clipboard respects that choice.

For isolated manual review:

```sh
build/Clipboard.app/Contents/MacOS/ClipboardHost --review --data-dir /tmp/clipboard-review
```

Review mode still observes the shared clipboard. Quit it when finished.

Run history retention, image restore, and search shortcut checks with `./tests/run.sh`. They use temporary profiles, a private test pasteboard, and a test window without accessing your current clipboard or Keychain.
