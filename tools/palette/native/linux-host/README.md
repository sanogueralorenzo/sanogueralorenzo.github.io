# Linux host

This host uses GTK4/libadwaita for the native shell and WebKitGTK for the
shared React frontend. It is intentionally a thin shell: command execution,
clipboard policy, persistence, and indexing remain in the Node/Rust services.

The host now creates a WebKitGTK `palette` message handler and forwards
requests/responses to the same resident Node sidecar used on macOS and
Windows. `PALETTE_NODE_DAEMON` can point at a packaged `.mjs` or development
`.ts` daemon.

When the launcher window is focused, `PALETTE_HOTKEY` (default `Alt+Space`)
toggles it as a local fallback; a true desktop-wide shortcut still belongs in
the portal integration below.

The remaining desktop integration should add:

- A StatusNotifierItem (the desktop-equivalent of a macOS menubar icon) for
  open, clipboard history, recent actions, settings, and quit.
- The XDG Desktop Portal GlobalShortcuts API for configurable accelerators and
  chord state handling where the desktop environment supports it.
- The XDG Desktop Portal OpenURI and Secret APIs for opening results and
  provisioning the clipboard encryption key.

`PALETTE_UI_PATH` may point to the Vite-built `dist/ui/index.html` during local
development.
