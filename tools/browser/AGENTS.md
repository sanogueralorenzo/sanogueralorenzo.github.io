# Lean

- Use native macOS controls with SwiftUI/AppKit and WebKit.
- Keep browser state and UI on `MainActor`; handle external callbacks explicitly.
- Preserve Space isolation, private browsing, session recovery, and closing/download safeguards. Never discard unreadable session data silently.
- Build the affected configuration and run focused checks. Use disposable test profiles with `LEAN_REVIEW_DATA_DIRECTORY` and distinct bundle IDs for review builds. Keep temporary artifacts outside the checkout and clean up review apps afterward; never use the personal profile for fixtures.
