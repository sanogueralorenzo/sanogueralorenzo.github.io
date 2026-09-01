# Palette runtime audit

Audit date: 2026-08-31
Baseline: `28ce317e24e9efe46a862547e559d1e1c62ef12c`

## Decision

Repair and simplify the existing implementation. The shared React/TypeScript
interface, Node service boundary, direct-process runner, encrypted clipboard
store, and Rust indexer are useful, independently tested work. The failures
were concentrated in native lifecycle behavior and reproducible packaging, so
a rewrite would have increased risk without addressing the root causes.

## Baseline evidence

- `npm run typecheck`, all 18 baseline TypeScript tests, the production Vite
  build, the bundled Node daemon, and the Rust release build passed.
- Rust indexer unit tests and macOS Swift typechecking passed.
- A manually assembled and ad-hoc-signed app existed at
  `~/Applications/Palette.app`; LaunchServices kept its AppKit process resident
  and its Node daemon was observable as a child process.
- The repository had `Info.plist` metadata but no script that assembled that
  working bundle, no packaged Rust indexer lookup, and no app launch test.
- The local machine did not have .NET 8 or GTK4/WebKitGTK development packages,
  so Windows/Linux host runtime validation belongs to their CI runners.

## Baseline runtime failures

### macOS

- The `NSPanel` used titled/closable document-window chrome.
- Every reopen called `makeLauncherWindow`, replacing the prior WebView.
- Escape called browser `window.close()`, which is not a reliable native panel
  dismissal mechanism in WKWebView.
- There was no click-outside dismissal or previous-application focus restore.
- UI/daemon resources worked only when somebody manually copied them into the
  expected `Bundle.main` subdirectories.
- Node lookup still fell back to terminal PATH behavior, and the Rust indexer
  was resolved from the launch working directory rather than the bundle.
- `~/.palette/commands.json` was documented, but the macOS daemon looked for it
  in Application Support alongside mutable data.

### Windows

- Startup constructed and hid the window before `Loaded`; WebView2 and the
  global hotkey therefore did not initialize until the tray first showed it.
- Manual launch had no visible feedback.
- The project did not copy production UI/daemon resources to build output.
- Node lookup depended on PATH, and clipboard capture/native notifications were
  not connected.

### Linux

- UI and daemon paths were relative to the process working directory.
- Node lookup depended on PATH.
- Manual launch hid the only window.
- Escape/click-outside dismissal and clipboard capture were not connected.
- Tray and portal shortcut code existed, but CI only compiled the host without
  first producing the resources it consumes.

### Shared layers

- Silent process execution, output/error results, notification events,
  encrypted clipboard retention/exclusions, and run-history persistence were
  implemented and tested.
- Run history was not exposed through the bridge/UI.
- Command configuration approximated extensions, but no first-class local
  extension manifest loader existed.
- Chord matching and conflict detection were implemented and tested, but native
  hosts intentionally registered only the launcher accelerator.

## Implemented repair boundary

1. Preserve the shared service/core and add only missing run-history and local
   extension surfaces.
2. Make macOS a borderless reusable floating panel with native dismissal,
   focus restoration, explicit resident lifecycle, bundle-backed web scheme,
   deterministic helpers, and a reproducible app builder.
3. Make Windows initialize visibly on manual launch, package resources, resolve
   Node deterministically, stay resident on close, and bridge clipboard and
   notification behavior.
4. Make Linux use executable-relative resources, deterministic Node lookup,
   portal shortcut toggling, resident native dismissal, clipboard capture, and
   native notifications.
5. Validate shared/Rust and each native host in separate CI jobs; launch the
   packaged macOS app through LaunchServices in CI.

## Intentionally deferred

- A broad marketplace, AI, notes, canvas, and Electron.
- Automatic LaunchAgent installation. User-controlled Login Items are less
  surprising and avoid turning a background start into an unsolicited panel.
- OS credential-store adapters for Windows and Linux; their daemon key files
  remain local and permission-restricted until DPAPI/libsecret adapters ship.
- Native global registration of every command chord. The shared matcher and
  manifest contract are the integration path; the global OS reservation stays
  limited to the launcher shortcut.
