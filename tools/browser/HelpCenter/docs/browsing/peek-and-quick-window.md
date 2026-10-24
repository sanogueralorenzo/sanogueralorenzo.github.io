---
title: Use Peek and Quick Window
description: Preview links without losing your place and handle links opened from other apps.
slug: /peek-and-quick-window
keywords: [Peek, Quick Window, Tiny Arc, preview, external links, transient browsing]
---

# Use Peek and Quick Window

Peek and Quick Window are transient browsing surfaces. Both use a real Crest Space profile so the page can access the right signed-in session and Crest Passwords, but neither has to become a durable tab.

## Peek

Peek opens a link above the source page. Close it to return immediately, or choose the primary action to promote it into a full tab. **Command-W** closes an open Peek and **Command-O** promotes it.

In **Settings → Links**, you can automatically open cross-site links from pinned and saved tabs in Peek. You can also choose whether **Option-click** or **Command-click** explicitly opens Peek; the other modifier opens the link in a new tab.

Peek stays attached to its source tab when you open another tab or switch Spaces. Return to the source tab to continue in its Peek. If the source is one card in Split View, promotion and page commands follow that focused card.

### Pull a link into Peek on Mac

Drag a webpage link to pull out a live preview that follows your gesture and fades in as the page loads. Release to keep the preview open, then close it or promote it into a tab using Peek’s controls.

Choose this behavior in **Settings → Links → Drag links to Peek**. Hold **Option** to drag the link normally; when the setting is off, Option-drag opens Peek instead.

On iPhone and iPad, touch and hold webpage links for the native link preview and actions, including opening a link in another Space. Touch and hold an image for image actions such as saving it.

## Quick Window

Quick Window handles a link from another app without dropping it immediately into the durable sidebar. It uses the configured Space’s cookies and passwords. When the page matters, move it into a normal window and choose the right Space.

Open a blank Quick Window with **Option-Shift-Command-N** on Mac. In **Settings → Links**, choose whether external links use Quick Window, the most recent Space, or a chosen Space.

### Sign-in and other popup windows

When a page opens a popup window, like a **Sign in with Google** or **Sign in with Apple** window, Crest for Mac shows it in a Quick Window in the same Space. The popup stays connected to the page that opened it, uses the same engine as that page, and closes itself when the sign-in finishes. Choose **Open in** and the Space to keep it as a tab instead, or close the Quick Window to drop it. A page that opens a new tab, rather than a popup window, still opens a tab beside it. On iPhone and iPad, a popup opens as a tab.

## Shared windows and Blank Window on Mac

Use **Command-N** for another window onto your shared Spaces and tabs. Each window keeps its own selected Space and tab. Organizing or closing a tab changes the shared workspace; closing the window itself keeps your tabs available in the other windows.

When two windows show the same tab, the focused window holds the live page and the other displays its preview. Focus the other window to continue there with the same page state.

Use **Option-Command-N** for a **New Blank Window**: a disposable workspace using the current Space's cookies, passwords, extensions, and settings. Its tabs, folders, history, and archive are temporary, stay out of iCloud sync, and are discarded when the window closes. It shares the Space's signed-in website session; use a Private Space when you need temporary website storage too.

Drag a tab outside the window to move it into a blank window at the drop location. Move a tab back into a normal window to keep it in the shared workspace.

## Cleanup and remembered destinations

Quick Window records can auto-archive after **1, 6, 12, or 24 hours**, or remain until you remove them. Enable **Remember the chosen Space for each site** when repeated links from the same domain should return to the destination you previously chose.

Archived Quick Windows remain distinguishable in Archive so you can recover something you dismissed too quickly.
