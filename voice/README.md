# Voice Keyboard (Android IME)

Voice is an on-device voice keyboard built for speed, accuracy, and privacy.

- Dictation: Moonshine ASR (local)
- Rewrite/Edit: LiteRT-LM (local, optional)
- Output: commits text directly into the active input field
- Network: only for model/prompt downloads and update checks

## Why Voice

- Fast speech-to-text inside the keyboard
- Reliable local rewrite/edit when enabled
- No cloud inference in normal runtime
- Setup optimized to reduce taps (auto-download on Wi-Fi, auto-advance when ready)

## User Setup

1. Install and open the app.
2. Continue through intro.
3. Download required files (auto-starts on Wi-Fi).
4. Grant microphone permission.
5. Tap Continue to open Android keyboard settings and enable Voice Keyboard.
6. Tap Continue to open the IME picker and select Voice Keyboard.

## Key Files

- IME orchestration: `app/src/main/java/com/sanogueralorenzo/voice/ime/VoiceInputMethodService.kt`
- Keyboard UI/state: `app/src/main/java/com/sanogueralorenzo/voice/ime/VoiceKeyboardUi.kt`
- ASR: `app/src/main/java/com/sanogueralorenzo/voice/audio/MoonshineTranscriber.kt`
- Rewrite/Edit: `app/src/main/java/com/sanogueralorenzo/voice/summary/LiteRtSummarizer.kt`
- Models/updates: `app/src/main/java/com/sanogueralorenzo/voice/models/ModelCatalog.kt`
- Setup flow: `app/src/main/java/com/sanogueralorenzo/voice/setup/SetupFlowScreen.kt`

## Optional Prompt Evaluation

```bash
scripts/prompt_eval.sh --prompt-file examples/prompt_eval/prompt.txt --cases-file examples/prompt_eval/cases.jsonl --report-file .cache/prompt_eval/report.txt --json-report-file .cache/prompt_eval/report.json
scripts/prompt_ab_optimize.sh --prompt-a-file scripts/prompt_a.json --prompt-b-file scripts/prompt_b.json --dataset-file scripts/dataset.jsonl
```
