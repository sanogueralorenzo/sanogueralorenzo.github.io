# Voice (Android IME)

Voice is an Android keyboard (IME) focused on dictation:

1. Capture audio from the keyboard UI.
2. Transcribe on-device with Moonshine.
3. Optionally rewrite/edit on-device with LiteRT-LM (Gemma 3 1B IT).
4. Commit final text to the active input field.

No cloud inference is used during normal typing. Network is only used for model download and update checks.

## Runtime Flow

`tap` -> `AudioRecord (16kHz mono PCM)` -> `MoonshineTranscriber` -> `LiteRtSummarizer` -> `InputConnection.commitText(...)`

## Core Behavior

- Compose mode:
  - transcribes speech
  - applies LiteRT rewrite when enabled and available
  - falls back to raw transcript if rewrite fails
- Edit mode:
  - starts from current input text
  - first tries deterministic local edit commands (clear/delete/replace)
  - falls back to LiteRT edit when needed
  - if LiteRT edit fails, keeps original text

## Main Modules

- IME service: `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/ime/VoiceInputMethodService.kt`
- Keyboard UI and state:
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/ime/VoiceKeyboardUi.kt`
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/ime/VoiceKeyboardViewModel.kt`
- Audio recorder: `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/audio/VoiceAudioRecorder.kt`
- Moonshine ASR: `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/audio/MoonshineTranscriber.kt`
- LiteRT rewrite/edit: `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/summary/LiteRtSummarizer.kt`
- Model catalog/download/storage:
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/models/ModelCatalog.kt`
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/models/ModelDownloader.kt`
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/models/ModelStore.kt`
- Setup app screen: `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/setup/MainActivity.kt`

## Models

Configured in `ModelCatalog`:

- Moonshine medium-streaming English model pack (`.ort` + tokenizer/config files)
- LiteRT-LM model (`.litertlm`) for rewrite/edit

Optional mirror setting:

```bash
# gradle.properties (project or user)
VOICE_MODEL_MIRROR_BASE_URL=https://your-public-model-cdn.example.com
```

Mirror resolution applies to LiteRT specs. Download order is mirror first, canonical URL second.

## Build

```bash
./gradlew :app:assembleDebug
./gradlew :app:compileDebugKotlin
./gradlew :app:lintDebug
```

## Setup

1. Install and open the app.
2. Grant microphone permission.
3. Download Moonshine and LiteRT models.
4. Enable `Voice Keyboard` in Android keyboard settings.
5. Select `Voice Keyboard` in the IME picker.

## Notes

- Keep user-facing strings in `strings.xml`.
- Keep `ModelCatalog` metadata aligned with actual model artifacts.
