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
- Home UI: no top toolbar title; `Overlay` label is shown inside the intro card.
- Home permissions shortcut: shows `⚠️` + `Required to use Overlay` until setup is complete, then `✅` + `All Granted`.
- Home permissions shortcut updates automatically from one combined requirements status stream.
