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
focused checks with `npm run typecheck`, `npm test`, and `npm run build`. The
macOS shell is `native/macos/PaletteHost.swift`; it loads the bundled `dist/ui`
frontend when packaged and provides the resident status item and default
`⌥ Space` launcher shortcut.

Copy `commands.example.json` to `~/.palette/commands.json` to add direct-process
commands. Arguments are passed without a shell; use `mode: "silent"` for
background actions and assign either an accelerator or a chord shortcut.

On Linux, the resident host publishes a StatusNotifier tray item and registers
the launcher accelerator through the XDG Desktop Portal GlobalShortcuts API
when that portal is available. A focused-window GTK shortcut remains as a
development fallback. Command chords are matched by the shared shortcut
service after the launcher opens; desktop portals intentionally own only the
single global launcher accelerator.

Clipboard history is encrypted at rest. macOS supplies its key from Keychain;
the development Node daemon keeps a permission-restricted `clipboard.key` in
the data directory on other hosts until their native Secret-service adapter is
available. The clipboard view exposes a pause/resume capture control, while
retention, exclusions, and sensitive-content handling remain policy fields in
`settings.json`.
