# Architecture

Lean Next uses Crest’s SwiftUI and AppKit interface with WebKit on macOS.
The iPhone and iPad sources are retained. There is one WebKit binding; there
is no Chromium implementation or native C++ page bridge.

- `CrestShared/Features` and `CrestMac/Features` contain the existing product UI.
- `CrestShared/Application` owns native application behavior, including media
  sessions, downloads, command palette ranking, shortcuts, import review, page prompts, remembered permissions and launch isolation.
- `CrestShared/Infrastructure/WebKit` owns page operations, profile storage,
  permissions, document bridges and bundled uBlock Origin Lite.
- `CrestCore` currently owns session state, browser rules, SQLite persistence
  and sync records. Swift reads its observable models through `CrestCore`.

The [core boundary](Architecture/ControlPlane.md) still has generated codecs.
Local page operations, media-session decisions and launch isolation use Swift
directly. [State ownership](Architecture/CoreArchitecture.md) describes the
remaining core path.

Use disposable profiles and the separate Lean Next app identity for validation.
