---
title: Check an extension's status and details
description: See whether an extension is on, and find its errors and permissions in Chromium's extension manager.
slug: /extension-status
sidebar_label: Status & details
sidebar_position: 7
keywords: [extension status, enabled, extension error, extension manager, troubleshooting]
---

# Check an extension's status and details

Crest shows each extension's basic state in its own settings. Chromium's extension manager holds the detailed record: errors, permissions and site access.

## In Crest Settings

Open **Crest Settings**, select the Space in the sidebar, then select **Extensions**. Each installed extension has a row with:

- its name, version and description;
- **From Chrome Web Store** for store installations;
- the **Enabled** switch. Turning it off keeps the installation and its data in the Space.

Expand the row to see the permissions and website access Chromium reports, and to reach **Extension Settings**, **Manage Permissions in Chromium**, **Install a copy in other spaces** and **Remove Extension**.

## In Chromium's extension manager

For errors and every other detail, open the manager for the extension's Space:

- From the extension's action menu, choose **Manage Extension…** for that extension, or **Manage Extensions…** for the whole list.
- On the Space's Extensions page in **Crest Settings**, select **Chromium Extension Manager**.

The manager shows what Chrome's does, including errors the extension reported. Include them, with the extension version, Crest version and the steps that fail, in a bug report.

## An extension whose files are gone

If an extension is still turned on but its files are missing, Crest shows no toolbar tile and no settings row for it. Selecting its action reports that the extension is unavailable. Reinstall it from the Chrome Web Store.

Continue with [Troubleshoot an extension](./troubleshoot-partial-compatibility.md).
