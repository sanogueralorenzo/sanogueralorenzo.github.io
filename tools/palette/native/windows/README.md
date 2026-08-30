# Windows host

The Windows shell uses C#/.NET 8 with WPF and WebView2. It keeps the process
resident, owns the tray icon and launcher window, and registers the default
`Alt+Space` shortcut with `RegisterHotKey`. WebView messages are forwarded to
the same JSON-lines Node sidecar used by the macOS host.

The production host should provision the clipboard key with DPAPI or Windows
Credential Manager, and replace the debug WebView message hook with the typed
bridge transport. Build the project with the .NET 8 SDK on Windows.
