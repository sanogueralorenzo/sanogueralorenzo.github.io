# Lean

- This app is macOS-only: SwiftUI/AppKit controls and direct WebKit calls.
- Organize by feature; keep entry points thin and remove replaced code.
- `BrowserSessionOwner` owns the session; `BrowserStore` holds a window's presentation and selection.
- Preserve per-Space isolation, private data staying out of checkpoints, native recovery, and closing/download safeguards.
- Keep one durable JSON checkpoint and its validated recovery copy; never silently replace unreadable data with an empty session.
- Build the affected configuration and run focused checks. Keep temporary probes and artifacts outside the checkout.
- Launch review builds with a distinct bundle identifier and `LEAN_REVIEW_DATA_DIRECTORY`; never use a personal profile for fixtures.
- After review, quit, unregister, and remove test app copies without touching the installed app.
- Advance `Config/Version.xcconfig` by one patch for app changes; append a unique entry to `Documentation/ReleaseNotes.json` and preserve existing entry IDs.
- Keep the README to product basics and setup; do not add work logs.
