---
title: Troubleshoot an extension
description: Steps to try when a Chrome extension installs in Crest but a feature does not work.
slug: /troubleshoot-extension-compatibility
sidebar_label: Troubleshoot an extension
sidebar_position: 9
keywords: [extension not working, extension error, troubleshooting, Chromium extension manager]
---

# Troubleshoot an extension

Extensions run on Chromium, so most behave as they do in Chrome. When one doesn't, the cause is usually its Space, its site access, or a browser feature Crest draws differently from Chrome.

## Try these first

1. Check that you are in the Space where you installed it. Each Space has its own installations. See [Spaces and profile isolation](../spaces/spaces-and-isolation.md).
2. In **Crest Settings**, select the Space in the sidebar, then **Extensions**. Turn the extension off and back on.
3. Expand its row, select **Manage Permissions in Chromium**, and check whether its site access covers the page you are on.
4. Open **Extension Settings** if the extension has them, and check its own options.
5. Remove the extension and install it again from the Chrome Web Store.

## Read the error

Choose **Manage Extension…** from the extension's action menu to open Chromium's extension manager. It lists errors the extension reported. See [Check an extension's status and details](./status-and-technical-details.md).

## In a private window

Private windows use a fresh profile and do not inherit a Space's installed extensions. You cannot install or remove extensions there. Test the extension in its normal Space instead; enabling Chrome's incognito option does not copy it into Crest's separate private profile.

## Password managers and companion apps

If the extension needs a Mac app, such as 1Password or iCloud Passwords, the app decides whether to trust Crest. Use the signed and notarized Crest release, not a development build. See [Native companions](./native-companion-limits.md).

## Features Crest draws differently

Crest shows popups, side panels, extension windows and keyboard shortcuts in its own interface. An extension that expects part of Chrome's window that Crest does not draw may lose that feature. See [Extension compatibility](./api-compatibility-matrix.md).
