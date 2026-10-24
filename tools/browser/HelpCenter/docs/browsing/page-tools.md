---
title: Translate, read, and use page tools
description: Translate webpages on device, use Reader, find text, adjust zoom, share, and export pages.
slug: /page-tools
keywords: [translate, translation, languages, Reader, find, zoom, share, Markdown, PDF, web archive, print, reload]
---

# Translate, read, and use page tools

Page actions operate on the focused page. In Split View, click or tap a card first so the intended page owns the command.

On Mac, each page runs in Chromium or WebKit. Crest on iPhone and iPad uses WebKit. A few page tools depend on the page's engine, and this page notes where. To switch a page, see [Chromium and WebKit on Mac](./engines.md).

## Translate a page

Translate webpages on device using Apple’s Translation framework. Whole-page translation works on iPhone, iPad, and Mac, where it works on both Chromium and WebKit pages. On a Chromium page you can also select text and translate the selection from the page's context menu; it uses the same on-device translation.

On Mac, open the translation toolbar with **Shift-Command-L**. On iPhone and iPad, tap the address bar’s translation button for options, or touch and hold it to translate immediately.

Choose **Detect Language** or a source language, pick a target language, then translate. **Show Original** restores the page’s original text. Language availability depends on Apple’s support; Apple asks before downloading a language that is needed.

**Automatically Translate** is off by default. When enabled, Crest uses your preferred device language and languages already downloaded. Showing the original keeps that page untranslated until you navigate or reload.

Downloaded language packs are shared with other apps and remain on the device after Private Browsing ends.

## Read and search

- **Reader** converts a supported article into a focused reading surface. Use the page controls, menu, command palette, or assign a shortcut. Reader works on WebKit pages. On Mac, open a Chromium page in WebKit to read it in Reader.
- **Find in Page** uses **Command-F**. Step through matches and close Find when finished. On a Chromium page, Find shows how many matches there are and which one is selected; on a WebKit page, it shows whether there is a match.
- **Zoom In**, **Zoom Out**, and **Actual Size** use **Command-+**, **Command--**, and **Command-0**.

Set a default zoom for pages in **Settings → Appearance**, from **50% to 300%**.

## Video and audio

Use the sidebar’s Now Playing controls for eligible active media. On Mac, supported videos can open in **Picture in Picture**. Turn on **Picture in Picture when switching tabs** in **Settings → General** to start it automatically. Availability depends on the website and its player.

## Copy and share

- **Copy Page Link** uses **Shift-Command-C**.
- **Copy Page Link as Markdown** uses **Option-Shift-Command-C** and produces a title-and-URL link suitable for notes or issue trackers.
- **Share Page** opens the platform share sheet when available.

## Export

- **Print Page** uses **Command-P**.
- **Export as PDF** writes a portable rendered document.
- **Save Web Archive** saves the whole page in one file. A Chromium page saves an `.mhtml` file, and a WebKit page saves a `.webarchive` file.

**File → Open File…** offers the archive format of the focused page's engine. Chromium cannot open a `.webarchive`, and WebKit cannot open an `.mhtml` file.

Export and Share are available through menus and the command palette even when no default shortcut is assigned.

## Reload choices

**Command-R** performs a normal reload. **Shift-Command-R** reloads from the origin when a cached response is not what you need. **Command-.** stops the current load.

## Content and site controls

The contextual site controls also expose the page's engine, Reader and content blocking where the engine offers them, permissions, extension actions, and developer status. On Chromium pages, blocking ads and trackers comes from the extensions you install. Decisions for camera, microphone, automatic downloads, popups, or external-app handoff are remembered within the current Space.
