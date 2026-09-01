# Voice for Android

The Android app provides two local-dictation entry points: a microphone overlay for the keyboard
the user already uses, and an optional compact Voice keyboard.

## Ownership

- `product/` owns the launcher experience and product readiness.
- `overlay/` owns the existing-keyboard microphone target and focused-field insertion.
- `keyboard/` owns the compact IME and its recording animation.
- `models/` and `audio/` own the shared local Moonshine resources and microphone transcriber.

The overlay and compact keyboard are independent entry points over the same `MicTranscriber` flow.
