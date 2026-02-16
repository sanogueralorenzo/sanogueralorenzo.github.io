# Voice (Android IME)

Voice is an Android keyboard (IME) for on-device dictation and lightweight text cleanup.

Core flow:

1. Capture speech from the keyboard UI.
2. Transcribe locally with Moonshine.
3. Optionally rewrite or edit locally with LiteRT-LM.
4. Commit final text to the active input field.

No cloud inference is used in normal runtime. Network is only used for model downloads and update checks.

## Product Boundaries

- Android custom keyboard (IME) plus setup app.
- On-device transcription and on-device rewrite/edit.
- Session-safe final commit into current editor.
- Graceful fallback when LiteRT or ASR substeps fail.

## Runtime Pipeline

`tap -> AudioRecord(16kHz mono PCM) -> MoonshineTranscriber -> LiteRtSummarizer(optional) -> InputConnection.commitText(...)`

## Runtime Behavior

Compose mode:

- Transcribe speech.
- Rewrite with LiteRT only when enabled and model is available.
- If LiteRT fails, commit raw transcript.

Edit mode:

- Start from current input text.
- Run deterministic local edit commands first.
- Fall back to LiteRT edit when needed.
- If LiteRT edit fails, keep original text.

Deterministic local command families:

- Clear all.
- Delete term (`all`, `first`, `last` scope).
- Replace term (`all`, `first`, `last` scope).

LiteRT rewrite/edit execution:

- One-shot request per operation (no retries).
- Fixed timeout cap: `30_000ms`.
- Failures use a single exception payload with:
  - `type`: `invalid_argument`, `input_too_long`, or `unknown`
  - `litertError`: sanitized LiteRT/runtime message
- Local bypasses (rewrite disabled/model unavailable) are handled in IME orchestration, not as LiteRT failures.

## Architecture Summary

Main runtime modules:

- IME orchestration:
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/ime/VoiceInputMethodService.kt`
- Keyboard UI/state:
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/ime/VoiceKeyboardUi.kt`
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/ime/VoiceKeyboardViewModel.kt`
- Audio capture:
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/audio/VoiceAudioRecorder.kt`
- ASR:
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/audio/MoonshineTranscriber.kt`
- Rewrite/edit:
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/summary/LiteRtSummarizer.kt`
- Model lifecycle:
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/models/ModelCatalog.kt`
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/models/ModelDownloader.kt`
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/models/ModelStore.kt`
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/models/ModelUpdateChecker.kt`
- Setup app:
  - `/Users/mario/AndroidStudioProjects/sanogueralorenzo.github.io/voice/app/src/main/java/com/sanogueralorenzo/voice/setup/MainActivity.kt`

Threading model:

- Main thread: IME lifecycle, UI updates, final commit.
- `executor` single thread: send pipeline.
- `chunkExecutor` single thread: Moonshine streaming tasks.

## Reliability Invariants

- Commit only when session/package still matches.
- Cancel in-flight work on teardown and input changes.
- LiteRT backend tries GPU first, then CPU.
- Model files must pass expected size checks and strict SHA-256 when hash is configured.

## Debug Footer

Inline debug keeps only core rewrite diagnostics:

- `litert_attempted`, `litert_applied`, `litert_backend`
- `litert_error_type`, `litert_error`
- `edit_intent`
- Timings, input/output sizes, transcript/output samples, and commit status

## Models and Configuration

Configured in `ModelCatalog`:

- Moonshine medium-streaming English model pack (`.ort` set + tokenizer/config files).
- LiteRT-LM model (`.litertlm`) for rewrite/edit.

## Setup App Capabilities

- Microphone permission flow.
- Open IME settings and IME picker.
- Download required models with progress.
- Check model updates.
- Toggle LiteRT rewrite and set custom rewrite instructions.

## Build and Test

```bash
./gradlew :app:assembleDebug
./gradlew :app:compileDebugKotlin
./gradlew :app:testDebugUnitTest
./gradlew :app:lintDebug
```

## Prompt Evaluation on macOS

Use `scripts/prompt_eval.sh` to benchmark prompts against expected outputs on a local macOS LiteRT-LM runtime.

What it does:

- Downloads the Gemma `.litertlm` model (if missing).
- Clones/builds LiteRT-LM CLI (if missing).
- Runs cases sequentially (not in parallel).
- Writes both text and JSON reports.

Example:

```bash
scripts/prompt_eval.sh \
  --prompt-file examples/prompt_eval/prompt.txt \
  --cases-file examples/prompt_eval/cases.jsonl \
  --report-file .cache/prompt_eval/report.txt \
  --json-report-file .cache/prompt_eval/report.json
```

Case format (`jsonl` or `json` array):

- `id`: string case identifier.
- `input`: test input text.
- `expected`: expected output string.
- `match`: `exact`, `contains`, or `regex`.

Notes:

- This workflow uses an Android-like compose configuration by default:
  - sampler profile level 0 (`topK=1`, `topP=1.0`, `temperature=0.0`, `seed=42`)
  - `max_num_tokens=224`
  - backend policy `auto` (GPU then CPU fallback)
  - Android-like input/output normalization in the evaluator
- Prompt templates can include a trailing `User input` block with `{{input}}` (or `{input}`); it is stripped and treated as system instruction.

### Prompt A/B Optimization Loop

Use `scripts/prompt_ab_optimize.sh` to run a round-based A/B loop with a fixed protocol.

```bash
scripts/prompt_ab_optimize.sh \
  --prompt-a-file scripts/prompt_a.txt \
  --prompt-b-file scripts/prompt_b.txt \
  --dataset-file scripts/dataset.jsonl \
  --max-rounds 1 \
  --patience 1
```

What this loop enforces:

- Fixed evaluation protocol across rounds (same model/backend/dataset/timeout).
- Primary recommendation threshold: prompt B must improve pass-rate by at least `1.0` percentage points over prompt A.
- Winner metric and tie-break: pass count, then fail count, then latency.
- Guardrail: reject candidate if it regresses a critical category too much (`clean`/`noisy`, default max drop `3.0pp`).
- Recommendation-only mode: no prompt files are auto-modified.
- Suggested next challenger prompt is generated from loser failures.
- Full round logging with prompt text snapshots, reports, scores, and git head.
- Early stopping when no improvement reaches patience limit.

Artifacts are written to:

- `.cache/prompt_ab/run_<timestamp>/round_log.jsonl`
- `.cache/prompt_ab/run_<timestamp>/summary.json`
- `.cache/prompt_ab/run_<timestamp>/recommendation.md`
- `.cache/prompt_ab/run_<timestamp>/splits/train.jsonl`
- `.cache/prompt_ab/run_<timestamp>/round_*/loser_failure_pack.jsonl`
- `.cache/prompt_ab/run_<timestamp>/round_*/suggested_next_prompt_b.txt`

Optional holdout:

- `--use-holdout` enables an unseen validation split (`id % 5 == 0` by default).
- Use this when you start iterating multiple rounds and want overfitting protection.

## Device Setup

1. Install and open the app.
2. Grant microphone permission.
3. Download Moonshine and LiteRT models.
4. Enable `Voice Keyboard` in Android keyboard settings.
5. Select `Voice Keyboard` in the IME picker.

## Contributor Notes

- Keep user-facing text in `strings.xml`.
- Keep `ModelCatalog` metadata aligned with real artifacts.
- Keep this `README.md` as the single source for product behavior and architecture notes.
