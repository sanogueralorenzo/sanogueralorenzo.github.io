# Voice (Android IME)

Voice is an Android custom keyboard (IME) for dictation-style input:

1. Record speech from the keyboard UI.
2. Transcribe on-device with Moonshine medium-streaming.
3. Rewrite on-device with LiteRT-LM (disfluency cleanup, punctuation/casing normalization, intent-preserving edits).
4. Commit text into the active input field via `InputConnection`.

No cloud transcription/inference is required for normal operation. Network is only used for model downloads.

## Runtime flow

`Keyboard tap` -> `AudioRecord (16kHz mono PCM)` -> `MoonshineTranscriber` -> `LiteRtSummarizer` -> `commitText(...)`

## Edit command behavior

The IME uses a two-lane edit pipeline:

- Lane 1: deterministic local rules for short high-confidence edit commands.
- Lane 2: LiteRT fallback for ambiguous commands and local no-match recovery.

Deterministic command gate:

- instruction words `<= 10`
- instruction chars `<= 96`
- exactly one actionable command verb group
- explicit target required for target commands
- ambiguous pronoun targets (`it`, `that`, `this`, `thing`, `part`) are rejected from local lane

Supported local command families:

- `CLEAR_ALL`: `delete`, `clear`, `erase`, `wipe`, `remove`, `reset`, `start over`, `scratch`
- `DELETE_TERM`: `delete`, `remove`, `erase`, `drop`, `cut`, `take out`, `get rid of`
- `REPLACE_TERM`: `replace`, `change`, `swap`, `substitute`, `use Y instead of X`

Scope support:

- default unscoped behavior: apply to all matches
- `first` / `only first`: first match only
- `last` / `final`: last match only

No-match policy:

- if local command is recognized but finds no target match, IME falls back to LiteRT edit
- if LiteRT fails, IME keeps the original input unchanged

## LiteRT rewrite contract

- Conservative rewrite by default (`edit, don't summarize`)
- Removes disfluencies/repairs and light ASR mistakes when unambiguous
- Never adds out-of-context suggestions or social filler
- Preserves numbers, links, and negation
- Intro preferences are applied conservatively unless explicit high-intensity terms appear:
  - `very`, `extremely`, `heavily`, `drastically`, `significantly`, `major rewrite`, `substantially`

## LiteRT stability guardrails

- Runtime is auto-tiered per attempt (`LOW` / `MEDIUM` / `HIGH`) using:
  - `ActivityManager.memoryClass`
  - `isLowRamDevice`
  - current `availMem` / `lowMemory`
- Each tier applies strict caps for:
  - engine token ceiling
  - rewrite input size
  - edit input size
  - rewrite output budget
- Memory guard:
  - if Android reports `lowMemory` or available memory is critically low, LiteRT is skipped and transcript/source text fallback is committed.
- Conversation lifecycle is hardened:
  - single active conversation marker
  - timeout -> `cancelProcess()` -> short grace delay -> close
- Native abort marker:
  - generation start is marked in shared prefs
  - marker is cleared on normal close
  - stale marker on next startup is reported as a suspected previous-run native abort in IME debug output.

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

- Moonshine medium-streaming English model bundle (`.ort` + tokenizer/config files) for transcription.
- LiteRT-LM model (`.litertlm`) for rewrite (`Gemma3-1B-IT`).

For non-gated LiteRT downloads, configure a public mirror base URL at build time:

```bash
# gradle.properties (project or user-level)
VOICE_MODEL_MIRROR_BASE_URL=https://your-public-model-cdn.example.com
```

`VOICE_MODEL_MIRROR_BASE_URL` supports:
- a base URL (`<base>/<subdir>/<fileName>`), or
- a direct `.litertlm` file URL.

Mirror resolution applies only to LiteRT model specs (`.litertlm`).
The downloader tries the configured mirror first, then falls back to the canonical URL in `ModelCatalog`.

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
- Need per-message diagnostics:
  - Enable the idle debug toggle in the IME to append a structured debug footer to the next committed output.

## Notes for contributors

- Keep user-visible text in `strings.xml`.
- Keep model URLs, sizes, and hashes in `ModelCatalog` consistent with runtime expectations.
