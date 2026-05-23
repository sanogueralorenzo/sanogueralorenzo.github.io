# Voice Engine

The engine is the shared deterministic text pipeline for Voice.

It owns platform-neutral pre-processing, post-processing, edit-command parsing, and guardrails. Platform apps should call the engine instead of reimplementing these rules, so Android, iOS, macOS, and web keep the same behavior for dictation cleanup and rewrite safety.

The engine boundary is:

```text
transcript -> engine preprocess -> platform LLM/runtime -> engine postprocess -> final text
```

Platform apps remain responsible for ASR, UI, keyboard or overlay integration, LLM runtime setup, storage, lifecycle, and telemetry.

Expected engine contents:

- Rule manifests that define enabled rules, phase, order, and parameters.
- A shared rule runtime that applies those manifests.
- Built-in operations for token, span, number, correction, edit, cleanup, and guardrail behavior.
- Conformance fixtures that every platform binding must pass.

## Rust Runtime

The current engine implementation is a Rust crate that exposes deterministic processing through:

- `preprocess(input)`
- `normalize_compose_input(text)`
- `normalize_instruction_input(text)`
- `clean_model_output(text, bullet_mode)`
- `normalize_compose_output_text(text)`
- `postprocess(original_text, model_output, list_mode)`
- `analyze_instruction(instruction_text)`
- `is_strict_edit_command(instruction_text)`
- `should_allow_blank_output(intent)`
- `try_apply_deterministic_edit(source_text, instruction_text)`
- `looks_like_list(text)`
- `post_replace_capitalization(source_text, instruction_text, edited_output)`
- JNI bindings used by the Android app.

The stable API contract is documented in [API.md](API.md). Any platform binding
must preserve that contract and pass equivalent conformance tests before it is
treated as compatible.

## Conformance Fixtures

Cross-platform fixtures live in `fixtures/*.json`. They are the source of truth
for binding compatibility and cover preprocess, normalization, postprocess, edit
analysis, deterministic edits, list detection, and replacement casing.

Every platform binding should add a small test runner that:

- Loads the fixture JSON files without rewriting or reordering cases.
- Calls the platform-native engine API for each case.
- Compares structured outputs exactly, including rule IDs, enum strings, null
  edit results, ordering, and boolean flags.
- Keeps platform-specific bridge encodings private; fixture assertions should use
  public structured values.

Android follows this pattern in `VoiceEngineConformanceTest`. Gradle passes the
shared fixture directory through the `voice.engine.fixtures.dir` test system
property, so the Kotlin binding tests read the same files as the Rust tests.

Run the engine tests from the repository root:

```shell
cargo test --manifest-path voice/engine/Cargo.toml
```

Android builds compile and package the Rust JNI library through `voice/android/app/build.gradle.kts`. A local Android SDK and NDK are required; Gradle reads `ANDROID_HOME`, `ANDROID_SDK_ROOT`, or `voice/android/local.properties`.
