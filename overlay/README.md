## Intro

**Overlay** is an Android app that provides a full-screen blackout overlay with quick-settings controls.

## Quickstart

### Build and install debug app

```shell
./gradlew :app:installDebug
```

## Reference

- Package: `com.sanogueralorenzo.overlay`
- Features:
  - Quick Settings tile: overlay on/off.
  - Optional long-press dismiss.
  - Optional auto-timeout lock tile.
  - Immersive status-bar toggle policy updates are idempotent (re-applying enable does not duplicate policy entries).
- Setup:
  - Grant "Display over other apps".
  - Add tiles in Quick Settings.
