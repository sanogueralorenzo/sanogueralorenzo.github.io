# Overlay

Tiny Android app that drops a full-screen black overlay so media keeps playing
and your screen stays dark. Toggle it from Quick Settings. There is also an
optional auto-lock timer tile.

## What it does
- Quick Settings tile to turn the black overlay on/off.
- Optional long-press to dismiss the overlay.
- Auto Timeout tile that locks the device after a timer (requires device admin).

## Setup
- Allow "Display over other apps" when prompted.
- Add the "Overlay" tile to Quick Settings.
- For Auto Timeout: enable device admin and add the "Auto Timeout" tile.

## Build
- Open in Android Studio and run on a device, or:
  - `./gradlew :app:assembleDebug`

## Stack
- Kotlin + Jetpack Compose + Mavericks + DataStore.
