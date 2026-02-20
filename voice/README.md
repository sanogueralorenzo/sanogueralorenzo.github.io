# Voice Keyboard (Android IME)

Voice is an on-device voice keyboard built for speed, accuracy, and privacy.

- Dictation: Moonshine ASR (local)
- Rewrite/Edit: LiteRT-LM (local)
- Output: commits text directly into the active input field
- Network: only for model/prompt downloads and update checks

## Why Voice

- Fast speech-to-text inside the keyboard
- Reliable local rewrite/edit
- Fully on-device runtime with no cloud inference
- GPU-accelerated inference when available
- Fastest experience out there, powered by live transcription and live LLM rewrite

## User Setup

1. Install and open Voice.
2. Download on-device models.
3. Grant microphone permissions.
4. Enable and select Voice Keyboard.

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

## License

- This repository code is licensed under MIT. See `LICENSE`.
- Gemma 1B IT (LiteRT) model usage is governed by:
  - [Gemma Terms of Use](https://ai.google.dev/gemma/terms)
  - [Gemma Prohibited Use Policy](https://ai.google.dev/gemma/prohibited_use_policy)
- See `legal/GEMMA_NOTICE.md` for the Gemma notice included with this project.
