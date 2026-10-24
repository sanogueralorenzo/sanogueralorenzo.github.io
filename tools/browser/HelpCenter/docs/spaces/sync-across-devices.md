---
title: Sync Crest across devices
description: Use iCloud to synchronize durable Spaces and resolve a device-versus-cloud conflict safely.
slug: /sync-across-devices
keywords: [iCloud, CloudKit, sync, conflict, Mac, iPad, iPhone]
---

# Sync Crest across devices

Open **Settings → Sync** and enable **Sync Crest with iCloud** on each device signed into the same Apple Account.

## What sync carries

Crest synchronizes durable browser structure such as Spaces, tabs, saved folders, Split View groups, appearance, Archive, history, and supported preferences. Mac, iPad, and iPhone then render the same model in an interface suited to the screen.

Password values never enter CloudKit. Each Space’s separate **Sync with iCloud Keychain** switch controls its encrypted Crest Password items. Private Spaces and transient Quick Window or Peek state are not normal synced browsing state.

## Check status

The Sync page shows whether iCloud is available and whether Crest has pending records. Apple does not expose the Apple Account email to Crest, so confirm the account directly in System Settings if two devices do not meet.

## Resolve a conflict

If Crest finds different local and cloud histories, it pauses instead of merging or overwriting silently. Choose **Use This Device** only when its copy should replace iCloud. Choose **Use iCloud** only when the cloud copy should replace this device. Read the confirmation carefully because the selected copy becomes authoritative for subsequent sync.

