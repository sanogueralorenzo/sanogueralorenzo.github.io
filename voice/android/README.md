## Intro

**Voice** is an Android local-first voice keyboard (IME) with on-device ASR and rewrite.
Post-rewrite cleanup converts unambiguous multi-word spoken number phrases such as "one, two, three" and "three hundred twenty one" into digits.
The overlay positioning screen keeps the bubble visible while a non-Voice keyboard is open, and tapping the bubble starts/stops overlay recording.

## Quickstart

```shell
./gradlew :app:installDebug
```

The Android app depends on the shared Rust engine in `../engine` for deterministic pre/post processing. Gradle builds the JNI library during Android packaging, so local builds need Rust, the Android SDK, and an installed Android NDK.

## Reference

- Package: `com.sanogueralorenzo.voice`
- Module: `voice/android/app`
- Version catalog: `voice/android/gradle/libs.versions.toml`
- Runtime models: Moonshine ASR + LiteRT-LM rewrite/edit.
- Text engine: `voice/engine`
