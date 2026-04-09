## Intro

**Voice** is an Android local-first voice keyboard (IME) with on-device ASR and rewrite.
The overlay positioning screen keeps the bubble visible while a non-Voice keyboard is open, and tapping the bubble starts/stops overlay recording.

## Quickstart

```shell
./gradlew :app:installDebug
```

## Reference

- Package: `com.sanogueralorenzo.voice`
- Module: `voice/android/app`
- Version catalog: `voice/android/gradle/libs.versions.toml`
- Runtime models: Moonshine ASR + LiteRT-LM rewrite/edit.
