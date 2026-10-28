---
title: Extension compatibility
description: Which extensions Crest runs, where, and which Chrome extension features Crest connects to its own interface.
slug: /extension-api-compatibility
sidebar_label: Extension compatibility
sidebar_position: 8
keywords: [extension compatibility, Chrome extension, Chromium, side panel, extension shortcuts, iCloud Passwords]
---

# Extension compatibility

Extensions in Crest for Mac run on the Chromium engine. Chromium runs each extension itself, with its own background service worker, APIs and permission checks, so an extension behaves much as it does in Chrome. Crest connects the parts that appear in a browser window, such as the toolbar, popups, side panels and shortcuts, to its own interface.

## Where extensions run

| Where | Extensions |
| --- | --- |
| Chromium pages in Crest for Mac | Chrome extensions from the Chrome Web Store |
| WebKit pages in Crest for Mac | None |
| Crest on iPhone and iPad | None |

Crest does not install Firefox add-ons or Safari Web Extensions. Many of them also publish a Chrome version. See [Firefox add-ons](./install-firefox-add-ons.md) and [Safari Web Extensions](./scan-safari-web-extensions.md).

## Packages

| Package | Support |
| --- | --- |
| Chrome Web Store extensions | Supported. Chromium checks the publisher's signature and the extension's ID before Crest shows its install review. |
| Extensions in more than one Space | Each Space gets its own installation and data. A copy reuses your approval only when the extension's identity, version and permission warnings match what you reviewed. |
| Unpacked extensions | For development. Install them from Chromium's extension manager in developer mode, linked from each Space's Extensions page in Settings. |
| Firefox `.xpi` packages | Not supported. |
| Safari Web Extensions, Safari content blockers, Safari App Extensions | Not supported. |

## Browser features extensions use

| Feature | In Crest |
| --- | --- |
| Toolbar actions and popups | The action appears in the Space's extension strip or in Site Controls. Its popup opens below the button in a window attached to the Crest window. Pinned actions belong to the Space, so they appear even on the Start Page. |
| Side panels | `chrome.sidePanel` opens as a card beside the page it belongs to. The action's context menu, an icon click set to open the panel, and `sidePanel.open()` and `close()` all reach that card. |
| Keyboard shortcuts | `chrome.commands` shortcuts work when Crest's own shortcuts do not use the same keys. Change them on Chromium's extension shortcuts page, linked from each Space's Extensions page in Settings. See [Set extension keyboard shortcuts](./keyboard-shortcuts.md). |
| New windows | `chrome.windows.create` opens a Crest window in the Space that owns the extension's profile. A popup window, such as a password manager's popout, opens as a tab in the current window instead, and the extension can still find, move and close it as its own window. A requested window state is ignored. A request no Space can host fails with an error. |
| Tab groups | A group an extension makes with `chrome.tabs.group` or `chrome.tabGroups` appears as a folder in the Space's open tabs, with the group's name and color. Renaming, recoloring, collapsing or deleting the folder, or moving tabs into or out of it, changes the group, and the extension sees the change. A pinned or saved tab an extension groups stays where it is. After Crest restarts, the folder keeps following the group, which comes back under the same ID as its tabs load. This Mac keeps the link between folder and group; it does not sync to your other devices. |
| Signing in | `chrome.identity.launchWebAuthFlow` returns to the extension's own sign-in address, as in Chrome, so an extension that signs you back in on its own, such as Claude, stays signed in after Crest restarts. |
| Private windows | Private windows use separate profiles and do not run installed extensions. |
| Tab sharing and debugging bars | Chromium's confirmation bars, such as the one `chrome.debugger` shows, appear inside the page. |
| Updates | Chromium updates Chrome Web Store extensions and checks their signatures and permissions. |
| Native companion apps | Supported through `nativeMessaging`. When a companion app registered its helper only for Google Chrome, Crest also looks in Chrome's locations. A helper still answers only the extensions it lists. See [Native companions](./native-companion-limits.md). |

## Known limits

- Crest's registration of the Chromium engine states that full extension API parity is not complete. Features that need a Chrome browser window Crest does not draw may be missing.
- Apple's iCloud Passwords helper checks the browser's signature and entitlements before it pairs. See [iCloud Passwords in Crest](./icloud-passwords.md).
- An extension that is still enabled but whose files are gone shows no toolbar tile or settings row, and its action reports that it is unavailable.

For package-specific native limits, continue with [Native companions](./native-companion-limits.md).
