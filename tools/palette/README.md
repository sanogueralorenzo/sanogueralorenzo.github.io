# Palette

Palette is a minimalist, keyboard-first desktop launcher. It provides one fast
place to find apps and files, run commands, and invoke small extensions without
turning the launcher into a full desktop environment.

## Product principles

- Open instantly, search immediately, and dismiss cleanly.
- Keep the default experience small; add capabilities through extensions.
- Rank local results quickly and predictably.
- Prefer native operating-system behavior for windows, shortcuts, permissions,
  accessibility, and menus.
- Keep user data local by default and make background work observable.

## Architecture

Palette uses the operating system's native WebView inside a thin platform host,
backed by shared application services and a portable high-performance core.

| Layer | Technology | Responsibility |
| --- | --- | --- |
| Shared interface | React + TypeScript | Launcher UI and extension surfaces shared by every platform |
| Application services | Node.js + TypeScript | Commands, extensions, database access, and background services |
| macOS host | Swift + AppKit + WKWebView | Windows, global shortcuts, menus, permissions, and native integration |
| Windows host | C# + .NET 8/WPF + WebView2 | Windows, global shortcuts, tray integration, permissions, and native integration |
| Linux host | Rust + GTK4/libadwaita + WebKitGTK | Windows, global shortcuts, desktop portals, menus, and native integration |
| Portable core | Rust | File indexing, search primitives, data models, and synchronization |

Typed IPC contracts connect the host, WebView frontend, Node.js services, and
Rust core. Platform-specific code stays in each host; product behavior stays in
the shared TypeScript layers; performance-sensitive or portable systems code
stays in Rust.

## Initial scope

1. Global shortcut and launcher window.
2. App, command, and file search.
3. Keyboard navigation and action execution.
4. Local settings and result ranking.
5. A small, permission-aware extension API.

Everything else should earn its place through demonstrated user need.

## Development

The platform-neutral core and preview launcher live in `src/`. Install the
package dependencies, then use `npm run dev` for the React preview or run the
checks with `npm run typecheck` and `npm run build:all`. The current
[clipboard improvement goal](development/GOAL.md) requires independent reviewer
iterations and manual runtime verification; do not create or run automated tests.
Use `http://localhost:5173/?preview` for synthetic clipboard layout development.
That browser preview has no access to the system clipboard or direct paste.

### macOS

Build a self-contained, ad-hoc-signed application with the production UI,
Node daemon, Node 22 runtime, and Rust indexer:

```sh
cd tools/palette
npm ci
npm run build:macos
open build/Palette.app
```

The first build downloads the official Node 22 runtime and verifies it against
Node's published SHA-256 manifest. To install locally, quit any older Palette instance,
then copy `build/Palette.app` to `~/Applications/Palette.app` and open it once.

Palette is an accessory application: it has no Dock icon, opens its floating
launcher on manual launch, and stays resident after dismissal. The default
shortcut is `⌥ Space`. Configure it without relying on Finder's environment:

```sh
defaults write sh.palette.Desktop launcherShortcut 'ctrl+space'
```

Supported values are `option+space`, `ctrl+space`, `ctrl+shift+space`,
`cmd+space`, and `cmd+shift+space`. Restart Palette after changing it. Palette
does not install a LaunchAgent; automatic background launch is intentionally
left to the user's macOS Login Items choice so a manual launch remains visible
and background operation never appears unexpectedly.

### Commands and local extensions

Copy `commands.example.json` to `~/.palette/commands.json` to add direct-process
commands. Arguments are passed without a shell; use `mode: "silent"` for
background actions and assign either an accelerator or a chord shortcut. Chord
definitions are validated and conflict-checked in the shared shortcut registry;
the macOS host reserves the launcher and clipboard accelerators.

A local extension is a directory under `~/.palette/extensions` containing an
`extension.json` manifest. It is deliberately just a named group of direct
process commands—there is no remote marketplace or arbitrary in-process code:

```json
{
  "id": "project-tools",
  "name": "Project Tools",
  "commands": [
    {
      "id": "serve",
      "title": "Serve Project",
      "command": "./serve.sh",
      "mode": "silent"
    }
  ]
}
```

Relative executables and working directories resolve inside the extension
directory. Command output, failures, notifications, and recent run history are
available through the launcher.

### Other hosts

Windows requires Node 22, .NET 8, and the WebView2 runtime. Build the production
resources before `dotnet build native/windows/PaletteHost.csproj`. Linux
requires Node 22 plus GTK4, libadwaita, and WebKitGTK 6 development libraries;
use `npm run build:linux-host` after building the UI and daemon. The platform
README files contain the host-specific details.

On Linux, the resident host publishes a StatusNotifier tray item and registers
the launcher accelerator through the XDG Desktop Portal GlobalShortcuts API
when that portal is available. Desktop portals intentionally own only the
single global launcher accelerator.

### Clipboard on macOS

Open history with `⌘ ⇧ V` or the launcher's Clipboard command. The clipboard panel
groups history by app, with All apps and Pinned views, combined search/type/app
filters, and text, link, image, and file previews. Select a row to preview it;
use Copy to restore its native formats, or Return to paste into the previously
active app. Direct paste requires macOS Accessibility permission for Palette.
Copy works without that permission. Files refer to their original locations;
restoration reports missing files rather than copying a path as text.

Use `⌘ F` to focus search, arrows to select, `⌘ C` to copy, `⌘ P` to pin/unpin,
and `⌘ K` for actions. With the history list focused, `⌘ ⌫` deletes and
`⌥ ⇧` plus up/down or left/right cycles app or type filters. Search keeps native
text-editing shortcuts. Escape dismisses the panel or its current dialog.

Pause/resume and Settings expose capture, retention, capacity, sensitive-content
handling, and excluded app identifiers. Pins survive retention and count limits;
reducing either removes older unpinned items. Capture supports text, HTML/RTF,
PNG/TIFF, file URLs, and links, with an 8 MiB per-copy payload limit and a 64 MiB
serialized-history limit. Images over 40 megapixels or 16,000 pixels on an edge
are skipped with an error. Thumbnails are downsampled before display.

Source apps are inferred from the foreground app when the clipboard changes,
including the outgoing app on activation changes. macOS does not provide an
authoritative writer identity: background writers can be mislabeled, and app
exclusions therefore cannot guarantee exclusion of background writes. Sensitive
pasteboard markers and obvious credential-shaped text are skipped when enabled;
this does not detect every secret.

Clipboard history is encrypted at rest. macOS supplies its key from Keychain;
the development Node daemon keeps a permission-restricted `clipboard.key` in
the data directory on other hosts until native DPAPI/Secret-service adapters
are available. Native capture and restoration of rich clipboard formats in this
iteration is macOS-specific; other hosts report unsupported rich restores.

For isolated native review, launch the built app with `--review --clipboard
--data-dir /absolute/path/to/review-profile`. Review mode requires a separate
data directory and uses a local permission-restricted random key instead of
Keychain. Pause capture between checks and use synthetic content; the system
clipboard is still shared with other apps. See [verification evidence](development/VERIFICATION.md)
and the [independent reviews](development/reviews/).
