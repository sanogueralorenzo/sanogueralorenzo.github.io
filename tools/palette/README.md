# Palette

A quiet macOS clipboard utility. Copy something, find it by its source app, and reuse it.

Click the overlapping-squares menu bar icon or press **⌘⇧V** to open a 280 × 300 panel beneath that icon, with its left edge aligned to the icon and extending right. The panel stays within the screen edges. Click search (or press **⌘F**) to find clip content or a source app; for example, `whatsap` matches WhatsApp copies. Escape, the shortcut, or clicking away dismisses it.

- Hover a clip and press **⌘C** to restore its native formats and dismiss the panel. Paste normally wherever you need it.
- **↑ / ↓** selects a clip; **Return** or double-click pastes into the previous app. With the pointer outside the list, **⌘C** copies the keyboard selection.
- **Space** previews the hovered or keyboard-selected clip immediately after opening, replacing the list with a full-area text, link, image, or file preview. Press Space again to return; **⌘F** returns to search.
- Search and selectable preview text retain native text-editing shortcuts.

Direct paste needs Palette's existing macOS Accessibility permission; ⌘C works without it. If the destination cannot regain focus, the clip remains copied for manual paste. macOS does not report whether a destination accepted a paste.

Click the **Palette title** to pause or resume capture; its inline icon shows the available action. The **bin** immediately clears all saved clips, including legacy pinned clips, without confirmation. There is no options menu or settings panel. The bottom **Quit** row shows **⌘Q**; either quits Palette. Defaults are 200 clips and 30 days; existing retention, capacity, exclusions, and pins remain honored. Automatic cleanup removes only older unpinned clips.

## Clipboard and privacy

Supports plain text, web links, images (PNG/TIFF), files, and useful HTML/RTF formatting. Files refer to their original locations; unavailable files report an error before changing the clipboard. Old text-only records still copy as text. Old images without saved image data report that they cannot be restored.

History and thumbnails stay local, encrypted with AES-256-GCM and a key in macOS Keychain. Private/transient pasteboard markers and obvious credential-shaped text are always skipped. Excluded apps use macOS's foreground app at copy time. macOS supplies no authoritative clipboard-writer identity: background writes can be attributed to the foreground app, and exclusions cannot guarantee protection from those writes. Secret detection is deliberately limited; pause capture when handling sensitive material.

Each captured copy is limited to 8 MB; image decoding is bounded to 40 megapixels and 16,000 pixels per edge. The encrypted history payload is limited to 64 MB. Reaching that limit reports an error and preserves saved clips, rather than silently evicting them. If an operation fails, the pause/resume icon turns amber and its tooltip explains the failure. Details remain until the next explicit pause/resume or clear action; background success does not erase them. Unreadable settings, keys, or history pause capture and preserve existing files.

Existing `~/Library/Application Support/Palette/clipboard.json` history, pins, app provenance, native representations, retention, pause state, and exclusions remain compatible. The Keychain service/account and version-1 encrypted envelope are unchanged. The new implementation needs no migration export or replacement key. Pending writes finish before a normal Quit.

## Build and run

Requires macOS 13 or later and Xcode Command Line Tools:

```sh
cd tools/palette
./scripts/build-macos-app.sh
open build/Palette.app
```

The build compiles three Swift source files, renders the existing overlapping-squares icon, and ad-hoc signs the application. No package installation, downloaded runtime, Node daemon, WebView, or file indexer is needed. Quit the installed Palette before replacing `~/Applications/Palette.app` with `build/Palette.app`.

Palette has no Dock icon and stays resident when dismissed. It opens on a manual launch. Use macOS Login Items for automatic launch; `--background` suppresses the initial panel. The only global shortcut is ⌘⇧V. If another app owns it, the menu bar icon remains available.

For native verification with disposable synthetic content:

```sh
build/Palette.app/Contents/MacOS/PaletteHost --review --data-dir /tmp/palette-review
```

Review mode requires a separate absolute directory and uses its own permission-restricted `review.key`. It still observes the shared system clipboard; pause capture while inspecting other work. Do not launch the normal and review instances together.

## Ownership

- `PaletteHost.swift`: one panel, app lifecycle, native interactions, capture monitoring.
- `ClipboardSupport.swift`: supported pasteboard capture and restoration.
- `ClipboardStore.swift`: one serial owner for history, settings, encryption, and persistence.

Palette now supports macOS. The earlier launcher and incomplete Windows/Linux hosts were removed along with commands, extensions, file search, run history, shared services, IPC, Rust, Node, React, and their build/test infrastructure.

See [native verification](development/VERIFICATION.md) and independent [usability](development/reviews/minimal-usability.md) and [reliability](development/reviews/minimal-reliability.md) reviews. No automated tests were created or run for this refinement.
