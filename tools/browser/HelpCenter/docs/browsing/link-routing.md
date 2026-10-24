---
title: Route links to the right Space
description: Build Air Traffic Control-style URL rules that send external links to a chosen Crest Space.
slug: /link-routing
keywords: [link routing, Air Traffic Control, URL rules, external links, Space]
---

# Route links to the right Space

Link Routing is Crest’s equivalent of Arc’s Air Traffic Control: matching links opened from other apps can go to a specific Space before the normal external-link destination is considered.

## Create a route

1. Open **Settings → Links**.
2. In **Routing**, choose **New Route**.
3. Enter a URL pattern.
4. Choose **Contains** or **Exact**.
5. Choose the destination Space.

Routes are evaluated from top to bottom. Reorder them when a narrow rule should win before a broad one.

## Match deliberately

- **Exact** is best for one complete address that should always land in one Space.
- **Contains** is useful for a domain or stable path fragment, but a pattern that is too broad may catch unrelated links.

Start with the smallest meaningful domain or URL fragment, test a link from another app, then broaden only if needed.

## Relationship to Quick Window

Routing runs before the default **Links from other apps** choice. If no rule matches, Crest uses Quick Window, Most Recent Space, or the Chosen Space according to that default.

A route targeting a protected Private Space is hidden until that Space is unlocked. This prevents its URL patterns and destination identity from leaking through Settings.

