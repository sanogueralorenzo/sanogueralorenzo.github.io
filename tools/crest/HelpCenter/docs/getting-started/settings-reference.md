---
title: Settings reference
description: Find every major Crest setting and understand whether it applies globally or to one Space.
slug: /settings-reference
keywords: [settings, preferences, General, Tabs, Search, default search, search providers, command palette, Appearance, page zoom, app icon, Links, Quick Window, Peek, Engines, Chromium, WebKit, Shortcuts, Sync, Privacy, system permissions, Spaces, Passwords, Extensions, Advanced, Feature Flags, About, updates]
---

# Settings reference

Open **Crest → Settings** on Mac. On iPhone and iPad, open Settings from the browser interface. Some controls appear only on the platform that supports them.

On Mac and wider iPad windows, Settings opens as a browser tab and keeps your place when you switch away. In compact layouts, including iPhone, it opens as a dismissible sheet while your current page stays selected.

On Mac, the Settings sidebar lists General, Tabs, Search, Appearance, Links, Engines, Shortcuts, Sync, and Privacy, then each of your Spaces by name and crest, then Agents, Advanced and About. iPhone and iPad keep their own layout; see [iPhone and iPad](#iphone-and-ipad).

## General

Make Crest your default browser, choose what happens when Crest opens, and pick the default Space. General also holds automatic page translation and spell checking. On Mac, it includes **Picture in Picture when switching tabs** and **Developer toolbar on local pages**. On iPhone and iPad, **Start on new tab** opens Crest on a new tab in the default Space, and **Allow floating sidebar** lets the sidebar float over the page instead of filling the screen.

## Tabs

Choose whether tabs opened from links get focus with **Switch to tabs opened from links**, and whether to **Follow tabs moved to another Space**. Set what pinned and saved tabs do after you close them, and whether clicking the favicon returns to the saved URL. Tabs also holds sidebar widgets and, on Mac, Split View's **Focus follows pointer** and **Show recent tabs while switching**, which shows your recent tabs while you hold Control-Tab.

## Search

- **Default search**: the search engine or AI assistant every Space uses unless it chose its own, the one **Private windows** use, and whether the default gives **Search suggestions**. **Tab to search providers** lets Tab choose a provider by its name or shortcut in the command palette, and **Space to search providers** lets a space after `$` and a shortcut, or after a shortcut alone, choose it.

The command palette settings come next:

- **Results**: show results under a header for each kind or **Blended** into one list, lead with a **Top Hit**, prefer an open tab over history for the same site, and **Show match reasons**, which notes under each result why it is there, such as "Often visited".
- **Sections**: turn each kind of result on or off, choose how many results each shows, and drag them into the order you want; **Reset Order** puts them back. Before you type, **Recent Tabs** and **Actions** show in this order.
- **Also show**: **Settings Pages**, **@ Filters** such as `@tabs`, the **Calculator** and, on Mac, **Paste and Go**, which offers the address you copied when the palette opens.
- **Typing**: complete addresses inline and learn from the results you choose. **Clear Learned Choices** forgets what the palette learned. Learned choices stay on this device.

The search providers come last:

- **Search Engines**, **AI Assistants** and **Websites**: every provider Crest offers, each with its main shortcut. Turn a provider off to stop its shortcut; the default stays on. Click a provider to open it and see its options, such as Google's **Hide AI Overviews** or ChatGPT's **Model**, and to change its shortcuts.
- **Add Provider…** adds your own search engine, AI assistant or website with a name, shortcuts, search URL and color. **Restore Defaults…** puts the built-in providers' shortcuts and options back; providers you added stay.

Search providers and their settings stay on this device.

See [Use the command palette](../browsing/command-palette.md).

## Appearance

Customize the browser on this device with a live preview. Choose sidebar position, the window border, tab shape and scale, pinned-tab layout, address-field style, folder display, and an app icon palette. With **Follow Space accent** on, selected tabs, pins, and the address field use the current Space's color; turn it off to pick a custom color. **Default page zoom** offers fixed levels from **50% to 300%**. Use presets to get started or reset individual changed settings.

A Space's crest, colors, and sidebar background live on the Space's Appearance page. See [Spaces](#spaces) and [Customize and arrange Spaces](../customize-spaces/).

## Links

Choose what happens to links from other apps, which Space supplies their signed-in session, and how long Quick Windows remain recoverable. Under Peek, choose whether eligible links from pinned or saved pages open in Peek, which modifier click opens it, and, on Mac, whether to **Drag links to Peek**. Link Routing rules live here too.

## Engines

On Mac, choose whether new pages open in Chromium or WebKit, and manage website rules that send particular websites to one engine. Chromium is the recommended default. See [Chromium and WebKit on Mac](../browsing/engines.md).

## Shortcuts

Search the complete Mac command catalog, record a replacement, inspect conflicts, clear an assignment, or restore the default. Extension shortcuts are set on Chromium's extension shortcuts page, opened from **Shortcuts…** on a Space's Extensions page, because they belong to the extension installed in that Space.

## Sync

Enable or disable iCloud sync and review its current state. Private Spaces and transient browsing are intentionally excluded.

## Privacy

On Mac, Privacy covers the whole device. **System permissions** shows whether macOS lets Crest use the camera, microphone, location, notifications, passkeys, and files and folders. Below that, select a Space to open its Privacy page, where its data retention, content blocking, and site permissions live.

## Spaces

On Mac, every Space has its own page. Select the Space in the Settings sidebar; the window switches to that Space, and Settings follows. The page header shows the Space's crest and name. Hover over the name and click the pencil to rename it, or open the **…** menu for more actions.

Each Space's page has these tabs:

- **Appearance**: Crest Studio for the Space's crest, colors, and sidebar background.
- **Browsing**: **Search with** and **Search suggestions**, which follow your default search until you choose for the Space, archiving old tabs with **Archive current tabs** and **Archive Now**, downloads (whether to ask where to save, and the download folder), and **Delete Space**.
- **Privacy**: **Require Touch ID or password**, how long to keep History, Archived Tabs, and Download Records, content blocking, and saved site permissions.
- **Passwords**: **Use Crest Passwords**, **Sync with iCloud Keychain**, and the Space's saved passwords, with **Import Passwords…** and **Export Passwords…**.
- **Extensions**: available when Chromium is. **Open Chrome Web Store**, **Chromium Extension Manager**, **Shortcuts…**, and the extensions installed in the Space.

### Add, arrange, and remove Spaces

Click **+** next to the Spaces heading to add a Space. Its Appearance page opens with the name ready to type. Click the pencil next to it to rearrange: drag Spaces by their handles, then click the checkmark when done.

Right-click a Space, or use the **…** menu on its page, for **Rename**, **Edit Crest…**, **Move Up**, **Move Down**, **Lock Space**, and **Delete**. Crest needs at least one Space.

## Agents

On Mac, choose whether coding agents on your Mac may use Crest, which Spaces they reach, and whether they may run scripts in pages; connect an agent, and see the agents connected now and the ones you allowed. See [Let coding agents use Crest](../browsing/coding-agents.md).

## Advanced

Import and export browser data, access runtime and diagnostic controls, and manage developer-facing behavior. Change advanced options deliberately; many of them exist to diagnose a specific browser or engine condition rather than improve everyday browsing.

On Mac, the **Feature Flags** row opens Chromium's feature flags for the current Space. Use the back arrow to return to Advanced.

Choose **Rerun onboarding** to return to Welcome and go through setup again. Completing setup opens Getting Started in your first Space, reusing its existing guide when available.

## About

**About** shows Crest’s build information and links to the community. On Mac, it also holds software updates: automatic checks and installs, the update channel, and **Check for Updates…**.

## iPhone and iPad

iPhone and iPad keep their own Settings navigation, with the same **Tabs** and **Appearance** pages for the whole device. **Spaces** is a page of its own: choose a Space from its picker to customize it and set its browsing and cleanup choices. **Privacy** also has a Space picker for data retention, content blocking, and site permissions. **Passwords** lists Crest Passwords by Space; authenticate to reveal or export them, and choose whether eligible credentials sync with iCloud Keychain.
