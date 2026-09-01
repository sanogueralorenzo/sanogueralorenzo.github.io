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
focused checks with `npm run typecheck`, `npm test`, and `npm run build:all`.

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
Node's published SHA-256 manifest. Run `npm run test:macos-app` for the
LaunchServices smoke test. To install locally, quit any older Palette instance,
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
native hosts reserve only the single launcher accelerator today.

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

Clipboard history is encrypted at rest. macOS supplies its key from Keychain;
the development Node daemon keeps a permission-restricted `clipboard.key` in
the data directory on other hosts until native DPAPI/Secret-service adapters
are available. The clipboard view exposes a pause/resume capture control, while
retention, exclusions, and sensitive-content handling remain policy fields in
`settings.json`.
