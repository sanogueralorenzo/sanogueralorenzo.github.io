# Voice for Android

The Android app is one product: local dictation through the keyboard the user already uses.

## Ownership

- `product/` owns the launcher experience and product readiness.
- `overlay/` owns the existing-keyboard microphone target and focused-field insertion.
- `models/`, `audio/`, and `asr/` own the local Moonshine runtime.

Keep product entry points small and keep transcription behavior owned by Moonshine.
