# Voice

Voice is a local-first voice input project built around a simple pipeline:

`capture audio -> transcribe -> clean or edit -> insert text`

## Structure

- `android/` contains the Android voice keyboard and floating input overlay.
- `engine/` contains shared deterministic text cleanup, edit commands, and guardrails.
- `evals/` contains shared prompts, datasets, and evaluation tools.

Android is the first supported platform. iOS, macOS, Linux, and Windows versions are coming soon.

## Development

```shell
cd voice/android
./gradlew :app:installDebug
```

Run the shared engine tests from the repository root:

```shell
cargo test --manifest-path voice/engine/Cargo.toml
```
