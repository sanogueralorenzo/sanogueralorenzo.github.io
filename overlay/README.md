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
- Window insets: `MainActivity` adjusts top status/cutout insets before Compose to keep app bar spacing compact with edge-to-edge.
