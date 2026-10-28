# Content blocking

WebKit uses bundled uBlock Origin Lite in Complete mode, including EasyList
Spanish (`spa-0`). Crest adapts the official Safari release to recognize
WebKit's extension scheme and report when its rules and scripts are ready.
The filtering algorithms and rules stay upstream-owned.

Each browsing profile has its own extension controller and storage. Private
profiles and isolated launches use memory-only controllers. Every navigation,
including restored pages and popups, waits for startup. Closing a page cancels
its pending navigation decisions. Startup failures remain visible in settings;
browsing may continue without protection until it can be enabled again.

The existing Space toggle controls the extension. Changing it reloads presented
pages while preserving background documents until their next navigation.
Deleting a profile unloads its extension and removes its extension data.

Refresh the bundle with:

```sh
python3 Scripts/update-ublock-origin-lite.py VERSION
```

The updater verifies the upstream SHA-256 and refuses unknown startup/runtime
layouts. Updates ship with Crest releases. The archive includes the modified
source and all upstream licenses; see `THIRD_PARTY_NOTICES.md`.
