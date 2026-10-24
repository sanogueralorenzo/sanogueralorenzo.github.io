---
title: Content blocking and site permissions
description: Control ads, trackers, camera, microphone, pop-ups, downloads, and external apps per Space.
slug: /content-blocking-and-site-permissions
keywords: [content blocking, ads, trackers, permissions, camera, microphone, pop-ups, downloads]
---

# Content blocking and site permissions

Privacy decisions belong to the current Space. A permission granted to a work account does not silently become a permission for the same host in Personal.

## Content blocking

Crest includes a small built-in ad and tracker ruleset that can be enabled or disabled per Space. It uses WebKit, so it applies on iPhone, iPad, and WebKit pages on Mac. Use the site controls or assign **Toggle Content Blocking** a shortcut when a site needs a quick exception.

To change it for a Space, turn **Block known ads and trackers** on or off in that Space’s privacy settings. On Mac, open Settings, select the Space in the sidebar, then select **Privacy**. On iPhone and iPad, open **Settings → Privacy** and choose the Space.

Chromium pages on Mac have no built-in blocking. Install a content-blocking extension, such as uBlock Origin Lite, in each Space that needs it. Extensions do not run on WebKit pages.

For broader filter-list coverage, install a content-blocking extension in the Space that needs it. Built-in protection and an extension can have different rule coverage, so check which layer is active before assuming the page itself is broken.

## Malicious sites and downloads

Crest's Chromium build keeps Google services disabled and does not include Google Safe Browsing or another built-in site and download reputation service. It cannot warn about every known phishing site or malicious download. Certificate checks, Chromium's sandbox, and warnings about executable or insecure downloads remain in place. Those checks do not determine whether a file is malware, and a completed download is not a safety verdict.

## Site permissions

Crest can remember decisions for:

- Camera
- Microphone
- Camera and microphone together
- Location
- Notifications
- Pop-ups
- Automatic downloads
- Opening external apps

Open Site Controls on the affected page to inspect or reset the decision. The Space’s privacy settings, in the same place as content blocking, list its saved site permissions.

Screen sharing asks what to share each time. You can block it for a site, but cannot preapprove a tab, screen or window. On pages that run in Chromium on Mac, Crest first lists the tabs in the same Space, and can share a tab's audio. Choose Window or Screen to use the macOS picker instead, which shares no audio. While a tab is shared, it and the sharing page show a bar with Stop sharing, and the shared tab is outlined in the sidebar. Minimize a bar to hide it until you come back to that tab. To stop from the sidebar, right-click either tab and choose Stop Sharing. Clicking the sharing symbol on a shared tab also offers to go to the tab it is shared to.

## Notifications

Allow the site in Crest and allow Crest in macOS notification settings to receive notifications. On Mac, **Settings → Privacy → System permissions** shows whether macOS allows it. Document notifications belong to their open page. Chromium also supports local service-worker and extension notifications while Crest runs, including a service worker's notification after its tab closes. Private profiles do not deliver these background notifications. Locking a Space or revoking its site permission withdraws notifications it can no longer show.

Remote Web Push delivery is not available in this Google-free Chromium build. Local service-worker notifications do not mean that a site can receive server pushes or wake Crest after it quits.

## Reset a site

If a site behaves as though an old choice still applies, first reset its saved permission rather than deleting the entire Space. Clearing all website data is broader: it can sign you out and remove local site state for that profile.

## Extension site access

Extension permissions are a separate layer. An extension may be installed but still blocked from the current host, or it may require approval for additional sites. See [Manage extension permissions and site access](../extensions/manage-permissions-site-access.md) for the extension-specific controls.
