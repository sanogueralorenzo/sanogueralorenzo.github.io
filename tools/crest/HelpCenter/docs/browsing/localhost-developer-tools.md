---
title: Localhost and developer tools
description: Preview phone, desktop, and custom viewport sizes, capture pages, and inspect websites with Crest’s Mac developer tools.
slug: /localhost-developer-tools
keywords: [localhost, developer mode, viewport, responsive, Web Inspector, DevTools, Chromium, console, network, capture]
---

# Localhost and developer tools

On Mac, Crest automatically shows its developer toolbar for local development addresses. This includes `localhost`, loopback and private-network addresses, single-label hosts, common local suffixes such as `.local` and `.test`, and file URLs.

Use **Shift-Command-I** to show or hide the toolbar on any website. To stop the toolbar opening by itself on local addresses, turn off **Developer toolbar on local pages** in **Settings > General**. The shortcut still shows it whenever you want it.

## Preview a different viewport

Choose a phone or desktop preset, or enter a custom size, in the developer toolbar. The live page renders within that viewport so you can review responsive layouts without resizing your whole browser window. Return to the normal viewport when finished.

This previews the page’s layout at the chosen dimensions; it does not reproduce another device’s hardware or browser engine.

## Toolbar controls

- Edit the complete development URL without losing the visible route.
- Copy the current link.
- Open Site Settings and inspect permissions.
- Use **Capture in Portrait Mode**, **Copy Full Page Capture**, or drag a region to copy it.
- Toggle the inspector's Console, Network panel, or element inspection.

Automatic localhost tools follow the focused address. The manual toolbar toggle lets you inspect other sites too.

## Open the inspector directly

Use **Option-Command-I**, the menu, or the command palette; the same shortcut closes it again. A Chromium page opens Chromium DevTools in the window, and a WebKit page opens Web Inspector. The inspector follows the focused page, including the focused card inside Split View.

## Security boundary

Developer tools make page internals visible and can change runtime state. Use them only for sites and code you trust. A certificate warning, external-app request, or protected permission remains subject to Crest’s normal navigation and site-permission policies; localhost mode does not bypass those checks.
