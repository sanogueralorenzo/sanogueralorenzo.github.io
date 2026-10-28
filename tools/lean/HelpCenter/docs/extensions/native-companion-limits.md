---
title: Native companions
description: How extensions in Crest for Mac connect to their companion Mac apps, and what those apps check.
slug: /native-companion-limits
sidebar_label: Native companions
sidebar_position: 8
keywords: [Crest for Mac, nativeMessaging, native companion, allowed_origins, password manager]
---

# Native companions

Most extensions need no desktop helper. A smaller group, with password managers the common example, uses `nativeMessaging` to talk to a separate Mac app.

## How Crest finds the helper

Extensions run on Chromium, which handles `nativeMessaging` as Chrome does. Each companion app registers a small manifest that names its helper and the extension IDs it will answer.

Most companion apps register only with Google Chrome. When Chromium's own lookup finds no manifest, Crest also checks Chrome's per-user and system `NativeMessagingHosts` folders. Chromium still checks the manifest's `allowed_origins`, so a helper answers only the extensions its app lists.

## The app decides whether to trust Crest

Some companion apps check the browser's code signature before they answer.

- **1Password** accepts a browser you add through its **Add Browser** setting, and checks that browser's signature. See [Set up 1Password in Crest](./onepassword.md).
- **iCloud Passwords** uses Apple's password helper, which Apple protects with a launch constraint on the browser's identity and entitlements. See [iCloud Passwords in Crest](./icloud-passwords.md).

Use the signed and notarized Crest release in `/Applications`. A development build carries a different signature, and companion apps that check the signature reject it.

## What Crest does not do

- Crest does not copy Chrome's profile or read a companion app's data.
- Safari app extensions and their native handlers do not work in Crest.

## Availability

Official Crest for Mac builds are signed with Developer ID, notarized, and published through GitHub Releases, with updates through a signed Sparkle appcast.
