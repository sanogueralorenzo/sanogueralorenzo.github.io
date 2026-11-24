# Browser

- Use native macOS controls with SwiftUI/AppKit and WebKit.
- Keep browser state and UI on `MainActor`.
- Preserve Space isolation, private browsing, session restoration, and closing and download safeguards. Save sessions atomically, start fresh only on confirmed corruption, and leave the file untouched on disk or permission errors.
- Build the affected configuration.
- Use only disposable profiles (`BROWSER_REVIEW_DATA_DIRECTORY`) and distinct bundle IDs for review builds. Keep review apps in the background, store temporary artifacts outside the checkout, and clean up afterward.
