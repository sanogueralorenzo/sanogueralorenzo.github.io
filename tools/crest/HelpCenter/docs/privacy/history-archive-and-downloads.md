---
title: History, Archive, downloads, and retention
description: Search, restore, remove, and retain browser records independently in each Space.
slug: /history-archive-and-downloads
keywords: [history, Archive, downloads, retention, restore, cleanup]
---

# History, Archive, downloads, and retention

History, Archive, and Downloads are common browser surfaces, but every record remains attached to the Space that created it.

## History

Open History with **Command-Y**, the menu, or the command palette. Search visits in the current Space and reopen a result. The command palette also includes relevant history matches while you type.

## Archive

Archive contains manually closed or archived tabs, automatic Space cleanup, and expired Quick Windows. Filter by reason when you know how the item left the sidebar. Restoring an archived tab returns it to an appropriate live position in that Space.

Use **Command-E** to archive the current tab, **Shift-Command-T** to reopen the last closed tab, and **Shift-Command-K** to clear unpinned current tabs into Archive.

## Downloads

Open Downloads with **Shift-Command-J**. Crest tracks status, destination, failures, and blocked automatic downloads. On Mac, each Space chooses its download folder, and whether to ask where to save each download, on its Browsing page in Settings. Removing or expiring a download record does not delete the downloaded file from disk.

Chromium downloads offer **Pause Download** while transferring and **Resume Download** when the engine can continue a paused or interrupted transfer. Depending on the server, resuming may restart the file. The same download record keeps its chosen destination. Cancel ends the transfer; removing a failed record does not retry it. WebKit downloads do not offer these pause and resume controls.

An unsafe-file warning requires its own decision. Resuming a transfer does not approve a warning or bypass a block. See [Malicious sites and downloads](./content-blocking-and-site-permissions.md#malicious-sites-and-downloads) for the limits of Chromium's Google-free protection.

## Retention per Space

On Mac, open Settings, select the Space in the sidebar, then select **Privacy**. On iPhone and iPad, open **Settings → Privacy** and choose the Space. Choose **1 Day, 1 Week, 30 Days, 90 Days, 1 Year, or Forever** independently for History, Archived Tabs, and Download Records.

Crest checks retention when it opens, after sync, and every 15 minutes while active. Shortening a duration can permanently remove older synchronized records, so Crest confirms the destructive change first.

Current-tab automatic cleanup is a different setting, **Archive current tabs** on the Space’s Browsing page on Mac. It archives old unpinned tabs after the chosen interval, keeping them recoverable until the Archive retention policy later expires them.
