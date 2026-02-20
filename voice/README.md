# Voice (Android IME)

Voice is an Android keyboard (IME) for on-device speech-to-text and optional local rewrite/edit.

- ASR: Moonshine (local)
- Rewrite/Edit: LiteRT-LM (local, optional)
- Final output: committed to the active input field
- Network use: model/prompt download and update checks only

## Runtime Flow

`tap mic -> record audio -> transcribe -> optional rewrite/edit -> commitText`

## What Users Get

- Dictation directly from the keyboard
- Optional cleanup/edit of dictated text
- Setup flow for mic permission, model download, and keyboard enable/select
- Update checks for models and prompt template

## Setup (End User)

1. Install and open the app.
2. Grant microphone permission.
3. Let required downloads complete (auto-start on Wi-Fi).
4. Enable Voice Keyboard in Android keyboard settings.
5. Select Voice Keyboard in the IME picker.

## Build and Test (Developer)

```bash
./gradlew :app:assembleDebug
./gradlew :app:testDebugUnitTest
./gradlew :app:lintDebug
```

Install and launch on a connected device/emulator:

```bash
./gradlew :app:installDebug
adb shell am start -n com.sanogueralorenzo.voice/.MainActivity
```

## Key Source Files

- IME entry and orchestration:
  - `app/src/main/java/com/sanogueralorenzo/voice/ime/VoiceInputMethodService.kt`
- Keyboard UI and state:
  - `app/src/main/java/com/sanogueralorenzo/voice/ime/VoiceKeyboardUi.kt`
  - `app/src/main/java/com/sanogueralorenzo/voice/ime/VoiceKeyboardViewModel.kt`
- Audio capture / ASR:
  - `app/src/main/java/com/sanogueralorenzo/voice/audio/VoiceAudioRecorder.kt`
  - `app/src/main/java/com/sanogueralorenzo/voice/audio/MoonshineTranscriber.kt`
- Rewrite / edit:
  - `app/src/main/java/com/sanogueralorenzo/voice/summary/LiteRtSummarizer.kt`
- Models and updates:
  - `app/src/main/java/com/sanogueralorenzo/voice/models/ModelCatalog.kt`
  - `app/src/main/java/com/sanogueralorenzo/voice/models/ModelDownloader.kt`
  - `app/src/main/java/com/sanogueralorenzo/voice/models/ModelUpdateChecker.kt`
- Setup flow:
  - `app/src/main/java/com/sanogueralorenzo/voice/setup/SetupFlowScreen.kt`

## Prompt Evaluation (Optional)

Run local prompt eval:

```bash
scripts/prompt_eval.sh \
  --prompt-file examples/prompt_eval/prompt.txt \
  --cases-file examples/prompt_eval/cases.jsonl \
  --report-file .cache/prompt_eval/report.txt \
  --json-report-file .cache/prompt_eval/report.json
```

Run A/B loop:

```bash
scripts/prompt_ab_optimize.sh \
  --prompt-a-file scripts/prompt_a.json \
  --prompt-b-file scripts/prompt_b.json \
  --dataset-file scripts/dataset.jsonl
```

## Notes for Contributors and Code Agents

- Keep user-visible copy in `app/src/main/res/values/strings.xml`.
- Keep this `README.md` as the single high-level source of truth.
- Prefer feature-scoped changes and update call sites/tests in the same change.
