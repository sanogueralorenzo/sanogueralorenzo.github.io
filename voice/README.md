# Voice (Android IME)

Voice is an Android custom keyboard (IME) for dictation-style input:

1. Record speech from the keyboard UI.
2. Transcribe on-device with Moonshine tiny-streaming.
3. Rewrite on-device with LiteRT-LM (disfluency cleanup, punctuation/casing normalization, intent-preserving edits).
4. Commit text into the active input field via `InputConnection`.

No cloud transcription/inference is required for normal operation. Network is only used for model downloads.

## Runtime flow

`Keyboard tap` -> `AudioRecord (16kHz mono PCM)` -> `MoonshineTranscriber` -> `LiteRtSummarizer` -> `commitText(...)`

## Important modules

- IME service and orchestration:
  - `app/src/main/java/com/sanogueralorenzo/voice/ime/VoiceInputMethodService.kt`
- Keyboard UI (Compose + Mavericks):
  - `app/src/main/java/com/sanogueralorenzo/voice/ime/VoiceKeyboardUi.kt`
  - `app/src/main/java/com/sanogueralorenzo/voice/ime/VoiceKeyboardViewModel.kt`
- Audio capture:
  - `app/src/main/java/com/sanogueralorenzo/voice/audio/VoiceAudioRecorder.kt`
- Moonshine ASR:
  - `app/src/main/java/com/sanogueralorenzo/voice/audio/MoonshineTranscriber.kt`
- LiteRT rewrite engine:
  - `app/src/main/java/com/sanogueralorenzo/voice/summary/LiteRtSummarizer.kt`
  - `app/src/main/java/com/sanogueralorenzo/voice/summary/SummaryPolicy.kt`
- Model catalog/download/storage:
  - `app/src/main/java/com/sanogueralorenzo/voice/models/ModelCatalog.kt`
  - `app/src/main/java/com/sanogueralorenzo/voice/models/ModelDownloader.kt`
  - `app/src/main/java/com/sanogueralorenzo/voice/models/ModelStore.kt`
- Setup app screen:
  - `app/src/main/java/com/sanogueralorenzo/voice/setup/MainActivity.kt`

## Models

Models are defined in `ModelCatalog`:

- Moonshine tiny-streaming English model bundle (`.ort` + tokenizer/config files) for transcription.
- LiteRT-LM model (`.litertlm`) for rewrite.

Storage location (internal app storage):

- `filesDir/models/moonshine/...`
- `filesDir/models/litertlm/...`

`ModelStore` enforces size/hash validation (strict mode where required) and caches verified state.

## Threading model

- Main thread:
  - Compose UI updates.
  - IME lifecycle callbacks.
  - Final `commitText(...)`.
- `executor` (single thread):
  - Main send pipeline: stop recording, finalize transcription, rewrite.
- `chunkExecutor` (single thread):
  - Streaming Moonshine frame ingestion and stream finalization.

The service cancels in-flight work on input/session teardown to avoid stale commits.

## Build commands

```bash
./gradlew :app:assembleDebug
./gradlew :app:lintDebug
./gradlew :app:compileDebugKotlin
```

## Setup / usage

1. Install and open the app.
2. Grant microphone permission.
3. Download Moonshine and LiteRT models on the setup screen.
4. Enable `Voice Keyboard` in Android keyboard settings.
5. Select `Voice Keyboard` in the system IME picker.
6. Use the keyboard pill UI to record/send.

## Troubleshooting

- Keyboard UI does not appear:
  - Ensure keyboard is both enabled and selected in system IME settings.
- Send finishes but no text is pasted:
  - Usually caused by input session changes in host apps. The service includes session guards and commit retry, but rapid focus switches can still cancel the result.
- Long transcribing time:
  - Device CPU class and audio duration dominate latency.
- LiteRT init fails:
  - Verify the downloaded `.litertlm` model matches the expected runtime format/spec in `ModelCatalog`.

## Notes for contributors

- Keep user-visible text in `strings.xml`.
- Keep model URLs, sizes, and hashes in `ModelCatalog` consistent with runtime expectations.
