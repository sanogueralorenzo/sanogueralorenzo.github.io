# Linux host

This host uses GTK4/libadwaita for the native shell and WebKitGTK for the
shared React frontend. It is intentionally a thin shell: command execution,
clipboard policy, persistence, and indexing remain in the Node/Rust services.

The production Linux integration should add:

- A StatusNotifierItem (the desktop-equivalent of a macOS menubar icon) for
  open, clipboard history, recent actions, settings, and quit.
- The XDG Desktop Portal GlobalShortcuts API for configurable accelerators and
  chord state handling where the desktop environment supports it.
- The XDG Desktop Portal OpenURI and Secret APIs for opening results and
  provisioning the clipboard encryption key.

`PALETTE_UI_PATH` may point to the Vite-built `dist/ui/index.html` during local
development.
