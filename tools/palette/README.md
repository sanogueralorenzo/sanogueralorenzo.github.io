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
