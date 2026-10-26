---
title: Install and update Crest for Mac
description: Download Crest directly, install it in Applications, and understand automatic updates.
slug: /install-and-update-mac
keywords: [download, install, update, macOS, GitHub Releases, Sparkle]
---

# Install and update Crest for Mac

Crest for Mac requires Apple silicon and macOS 26.1 or later. It is distributed directly as a signed and notarized app with Chromium and WebKit; see [Chromium and WebKit on Mac](../browsing/engines.md). Crest for iPhone and iPad is on the App Store and continues to use WebKit.

## Install the latest Mac release

1. Open the [latest stable Crest release](https://github.com/pauljoda/Crest/releases/latest).
2. Download its `Installer-….dmg` file.
3. Open the disk image, then drag Crest into **Applications**.
4. Eject the disk image and open Crest from Applications.

Alternatively, Crest can be installed via Homebrew:
1. Open Terminal.
2. Run `brew install --cask crest-browser`

Keeping Crest in Applications gives macOS and the updater one stable installed location. If Gatekeeper reports that the app cannot be verified, do not bypass the warning; download the current release again from the official Releases page.

## Automatic updates

Crest uses Sparkle to check for signed updates from inside the installed app. When an update is available, review the release, install it, and let Crest relaunch. Your Spaces and browsing data remain in their normal app storage rather than inside the application bundle.

Turn automatic checks and installs on or off in **Settings → About**, which also has **Check for Updates…**. You can also open the app menu and choose **Check for Updates**. A manual check uses the same signed update channel as the automatic check.

## Update channels

Use **Settings → About** to choose the update channel:

- **Stable** is the normal public release cadence.
- **Nightly** receives newer builds sooner and can change more frequently.
- **Development** follows the latest signed public `main` build and can change several times a day.

Changing channels changes which future update is offered; it does not move or duplicate your profile.

## Updating from an older Crest

The same installer updates older WebKit-only versions and versions that already include Chromium. Your Spaces and browser records stay in place. Chromium and WebKit keep separate website sign-ins, and older WebKit extension installations do not carry over. See [Upgrading from a WebKit-only Crest](../browsing/engines.md#after-updating-from-a-webkit-only-crest) before switching engines.

Crest checks pages for unsaved work before an update restart. Choose **Stay on Page** to keep working, then retry the restart when ready. Updates are offered only when your Mac meets the whole app's macOS requirement.

## iPhone and iPad

Install Crest for iPhone and iPad from the [App Store](https://apps.apple.com/us/app/crest-browser/id6797335023), or join the beta through [TestFlight](https://testflight.apple.com/join/vV1CM49Q). If iCloud sync is enabled, the same durable Space structure can follow you between Mac, iPad, and iPhone.
