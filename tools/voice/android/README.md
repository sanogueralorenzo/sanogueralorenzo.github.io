# Voice for Android

The Android app is one product: local dictation through the keyboard the user already uses.

## Ownership

- `product/` owns the launcher experience and product readiness.
- `overlay/` owns the existing-keyboard microphone target and focused-field insertion.
- `models/`, `audio/`, `asr/`, `summary/`, `engine/`, and the processing files in `ime/` are shared runtime implementation. The `ime/` name is retained for now to avoid renaming stable pipeline types without product value.
- `benchmark/` and `../../evals/` are developer tooling. Benchmark Android components are registered only in debug builds.

Keep product entry points small. Add shared abstractions only when both the overlay runtime and another shipping product need them.
