# Browser

- Use native macOS controls with SwiftUI/AppKit and WebKit.
- Keep browser state and UI on `MainActor`; handle external callbacks explicitly.
- Preserve Space isolation, private browsing, session restoration, and closing/download safeguards. Replace a session only after new data is saved atomically. Start fresh on confirmed corruption and leave the file untouched on disk or permission errors.
- Build the affected configuration and run focused checks. Use disposable test profiles with `BROWSER_REVIEW_DATA_DIRECTORY` and distinct bundle IDs for review builds. Keep temporary artifacts outside the checkout and clean up review apps afterward; never use the personal profile for fixtures.
- Launch review apps in the background with `open -gnj`. Use `open -gn` when a check needs a visible window, and avoid activating the review app.
