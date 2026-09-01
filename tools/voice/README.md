# Voice

Voice is private, local dictation for the keyboard you already use. Position Voice over your
keyboard's microphone, tap once to record, and tap again to insert clean text into the focused
field.

The product is built around a simple pipeline:

`capture audio -> transcribe -> clean or edit -> insert text`

When a field already contains text, Voice supports three deterministic command
forms:

- `clear everything`
- `delete milk` (or `delete milk and eggs`)
- `replace milk with oat milk`

## Structure

- `android/` contains the Android product UI and existing-keyboard microphone overlay.
- `engine/` contains shared deterministic text cleanup, edit commands, and guardrails.

Android is the first supported platform. iOS, macOS, Linux, and Windows versions are coming soon.

## Development

Install [rustup](https://rustup.rs/) and Android NDK `29.0.14206865`. The repository pins the Rust compiler and Android targets in `engine/rust-toolchain.toml`; the shared Cargo runner keeps builds independent of any Homebrew Rust installation.

```shell
cd tools/voice/android
./gradlew :app:installDebug
```

Run the shared engine tests from the repository root:

```shell
./tools/voice/engine/scripts/run-cargo.sh test
```
