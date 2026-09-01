# Windows host

The Windows shell uses C#/.NET 8 with WPF and WebView2. It keeps the process
resident, owns the tray icon and launcher window, and registers the default
`Alt+Space` shortcut with `RegisterHotKey`. WebView messages are forwarded to
the same JSON-lines Node sidecar used by the macOS host.

The project copies the production `dist/ui` and `dist/node` resources into its
build output. Build those resources before the WPF host:

```powershell
npm ci
npm run build:windows
```

The packaged build downloads and checksum-verifies the official Node 22
runtime, then places it and the Windows Rust indexer under `Helpers`. The host
otherwise resolves Node from `PALETTE_NODE_EXECUTABLE` or standard
per-machine/per-user Node installations.
Clipboard contents are encrypted by the shared daemon; a future signed
installer should replace the permission-restricted local key file with DPAPI.
