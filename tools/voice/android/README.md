# Voice for Android

The Android app provides two local-dictation entry points: a microphone overlay for the keyboard
the user already uses, and an optional compact Voice keyboard.

## Ownership

- `product/` owns the launcher experience and product readiness.
- `overlay/` owns the existing-keyboard microphone target and focused-field insertion.
- `keyboard/` owns the compact IME, its recording UI, and its audio-reactive animation.
- `models/` and `audio/` own the shared local Moonshine resources.

The overlay and compact keyboard remain independent products over the same downloaded model.
