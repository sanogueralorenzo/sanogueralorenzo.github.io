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

The host uses the XDG Desktop Portal GlobalShortcuts API for the configurable
launcher accelerator, captures text clipboard changes, and forwards native
notifications. Escape, close, and deactivation hide the launcher while leaving
the tray, WebView, and sidecar resident.

The remaining desktop-security integration is an XDG Secret/libsecret adapter
for the clipboard key. Until then, the daemon creates a permission-restricted
key under the Palette data directory.

`PALETTE_UI_PATH` may point to the Vite-built `dist/ui/index.html` during local
development.
