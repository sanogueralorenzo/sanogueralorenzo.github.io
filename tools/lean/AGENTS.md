# Lean

- Use the current Crest fork as the source of truth for product behavior and UI.
- Preserve existing WebKit features. Remove Chromium and unnecessary engine/interop architecture without rebuilding the browser from tools/browser.
- Keep changes organized by feature, entry points thin, and one authoritative owner for browser state.
- Use disposable profiles and a distinct app identity for validation; never use personal browser data or replace an installed browser.
- Run focused checks for behavior changes. Keep temporary validation artifacts outside the checkout and clean up review applications.
- Keep setup documentation brief and current.
