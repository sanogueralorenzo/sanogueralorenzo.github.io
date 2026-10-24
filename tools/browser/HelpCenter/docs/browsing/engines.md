---
title: Chromium and WebKit on Mac
description: Choose the engine new pages open in, send a website to the other engine, and see what each engine supports.
slug: /engines
keywords: [engine, Chromium, WebKit, ungoogled-chromium, default engine, website rules, protected video, DRM, FairPlay]
---

# Chromium and WebKit on Mac

Crest for Mac includes two web engines. New pages open in Chromium unless you choose otherwise, and any website or page can use WebKit, the engine behind Safari. Crest on iPhone and iPad uses WebKit.

Your Spaces, tabs, history, passwords and settings are the same whichever engine shows a page. Website data is not: each engine keeps its own cookies and storage for a Space, so signing in to a site in Chromium does not sign you in to it in WebKit.

## Chromium

Crest's Chromium engine is built on [ungoogled-chromium](https://github.com/ungoogled-software/ungoogled-chromium), which removes Google integrations from Chromium. It runs [Chrome Web Store extensions](../extensions/install-chrome-web-store.md).

Chromium starts the first time you need it. If WebKit is your default and no page uses Chromium, it stays unloaded. Opening a Chromium page or an extension starts it, and it stays running until you quit Crest.

## Choose the default engine

1. Open **Crest Settings → Engines**.
2. Select **Chromium** or **WebKit**.

The default applies to pages you open afterwards. Open pages keep their engine, and links a page opens stay on that page's engine. Select **Use Recommended Default** to return to Chromium.

## Open a website in the other engine

- **For one page:** choose **Page → Open Page in WebKit** or **Open Page in Chromium**. The page reloads in the other engine. Other pages from the site keep opening where they did.
- **For a whole website:** open Site Controls and change **Opens in**. The page reloads in that engine, and later pages from the website open there too.

A tab whose page runs in the engine that is not your default shows that engine's mark on its icon.

## Website rules

Choosing **Opens in** saves a website rule. Rules are listed under **Crest Settings → Engines → Website rules**, where you can:

- select **Add Website Rule…** to send a website to an engine before you visit it;
- select a rule to change its website or engine;
- select **Remove Rule** to return a website to your default engine.

Rules match the website's scheme, host and port. A rule for `example.com` does not cover its subdomains. A choice made while browsing privately is not saved as a rule; it lasts until you quit Crest.

## Protected video

Chromium in Crest cannot play DRM-protected video. When a page asks for it, Crest automatically switches to WebKit to try Apple's FairPlay support, unless you have explicitly chosen an engine for that website. The switch checks for unsaved work first. Choosing **Stay on Page** keeps the page in Chromium and leaves its website rule unchanged; repeated requests from that document do not prompt again. After an allowed move, the website opens in WebKit on later visits. Select **Move Back** to return it to Chromium, or remove its rule in Settings. Playback still depends on the site's support for FairPlay.

## After updating from a WebKit-only Crest

The previous stable 0.6 release used WebKit only. Updating to Crest 0.7 keeps your Spaces, tabs, history and Crest Passwords. New pages open in Chromium unless you choose WebKit as your default. Each engine keeps separate website data, so Chromium does not inherit your WebKit sign-ins. Your existing WebKit website data remains available to pages opened in WebKit.

Extensions installed in earlier versions do not carry over. Install them again from the Chrome Web Store.

## What each engine supports

| Feature | Chromium | WebKit |
| --- | --- | --- |
| Chrome Web Store extensions | Yes | No |
| Reader | No | Yes |
| Built-in ad and tracker blocking | No. Use a blocking extension. | Yes |
| Protected video | Automatically switches to WebKit after unsaved-changes checks | FairPlay, when the website supports it |
| Find in Page | Shows the number of matches | Shows whether there is a match |
| Save Web Archive | `.mhtml` file | `.webarchive` file |
| Inspect a page | Chromium DevTools | Web Inspector |

Tabs, Spaces, Split View, Peek, Crest Passwords, site permissions, Picture in Picture and downloads are available in both. Their engine controls can differ; Chromium downloads also offer pause and resume. See [Translate, read, and use page tools](./page-tools.md) and [Downloads](../privacy/history-archive-and-downloads.md#downloads) for details.

## Current Chromium limits

- Crest Passwords handles saved passwords. Built-in address and payment-card autofill are not available.
- Screen sharing offers your tabs in the same Space first, with their audio when the site asks for it. A window or your screen goes through the macOS picker, which shares no audio.
- Local service-worker and extension notifications work while Crest runs. Remote Web Push is not available.

See [Site permissions and notifications](../privacy/content-blocking-and-site-permissions.md) for permission controls and the Google-free engine's site and download protection limits.
