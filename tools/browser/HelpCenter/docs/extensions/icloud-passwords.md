---
title: iCloud Passwords in Crest
description: How the iCloud Passwords extension connects to Apple's password helper in Crest for Mac, and what Apple requires.
slug: /icloud-passwords
sidebar_label: iCloud Passwords
sidebar_position: 11
keywords: [iCloud Passwords, Password AutoFill, managed entitlement, Web Browser Public Key Credential Requests]
---

# iCloud Passwords in Crest

The iCloud Passwords extension installs from the Chrome Web Store into Crest for Mac and runs on Chromium pages. It is only half of iCloud Passwords. The other half is Apple's system password helper, which the extension reaches through native messaging.

## How the extension finds Apple's helper

Apple registers its helper for Google Chrome. Crest checks Chrome's native-messaging folders when Chromium's own lookup finds nothing, so the extension can reach it. Chromium still checks that the helper allows this extension. Crest does not read your passwords; Apple's helper controls authentication and access to them.

## What Apple checks

Apple protects its helper with a launch constraint on the browser. The browser must carry the managed **Web Browser Public Key Credential Requests** capability, or use an identity Apple has approved. The entitlement is:

```text
com.apple.developer.web-browser.public-key-credential
```

The signed Crest release carries this entitlement. Development and review builds do not, so iCloud Passwords cannot pair in them. Adding the entitlement to a build yourself does not authorize it; Apple checks it against the app's provisioning.

## If it does not pair

- Confirm that you are running the signed Crest release from `/Applications`.
- Reinstalling the extension does not change the browser's signature or entitlements.
- Until it pairs, use Crest's built-in passwords for the Space or another password manager.

## Official reference

- [Web Browser Public Key Credential entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.web-browser.public-key-credential)
