## Intro

**Overlay** is an Android app for full-screen blackout control via Quick Settings.

## Quickstart

```shell
./gradlew :app:installDebug
```

## Reference

- Package: `com.sanogueralorenzo.overlay`
- Module: `overlay/app`
- Key requirement: Android overlay permission enabled.
- App screens: Home, How it works, Permissions.
- Home UI: no top toolbar title; intro card uses a compact two-line hero (`Overlay` + `Play media with the screen off`).
- Home permissions shortcut: shows `⚠️` + `Required to use Overlay` until setup is complete, then `✅` + `All Granted`.
- Home permissions shortcut derives from one combined requirements stream backed by per-permission flows refreshed by Permissions screen actions and Home resume reconciliation.
