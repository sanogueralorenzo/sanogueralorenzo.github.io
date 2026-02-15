# Voice Keyboard Project Requirements

## 1. Product Scope

This project is an Android voice keyboard (IME) plus a setup app.

Core product goal:
- User records speech from the keyboard.
- Speech is transcribed on device.
- Transcription is rewritten/cleaned on device.
- Final text is committed into the active input field.

Hard constraints:
- No cloud inference for transcription or rewrite.
- Network is only used for model download/update checks.

## 2. Primary Components

- Setup app: `MainActivity` (Compose navigation).
- Keyboard runtime: `VoiceInputMethodService`.
- Audio capture: `VoiceAudioRecorder`.
- ASR: `MoonshineTranscriber`.
- Rewrite/edit: `LiteRtSummarizer`.
- Model lifecycle: `ModelCatalog`, `ModelDownloader`, `ModelStore`, `ModelUpdateChecker`.
- IME UI state: `VoiceKeyboardViewModel` + `VoiceKeyboardUi`.

## 3. Setup App Requirements

### 3.1 Main Activity and Navigation

- Activity title must be `Voice Keyboard`.
- Home screen must contain sections:
  - `Setup`
  - `Download Models`
  - `Onboarding`
  - `Calibration`
  - `Settings`
- Home screen must contain a bottom text input for keyboard testing.

### 3.2 Setup Section

- Must request microphone permission (`RECORD_AUDIO`).
- Must provide action to open Android input method settings.
- Must provide action to show IME picker.

### 3.3 Models Section

- Must show status/progress for each model group.
- Must support:
  - `Download all models` (required runtime models only).
  - Per-model download actions.
  - `Check for updates`.
- Must disable conflicting actions while a download/update operation is active.

### 3.4 Onboarding and Calibration Sections

- Onboarding must provide first-run guidance and quick links to setup/models/picker.
- Calibration must show readiness summary:
  - mic permission status
  - required model readiness status
  - quick actions to picker/settings

### 3.5 Settings Section

- Must expose `LiteRT rewrite` toggle.
- Toggle off behavior:
  - skip LiteRT rewrite for compose flow
  - skip LiteRT non-deterministic edit flow
  - still allow deterministic local edit commands
- Must expose persisted `Custom instructions` text input.
- Custom instructions must be injected into LiteRT rewrite/edit prompts when LiteRT is enabled.

## 4. Model Requirements

### 4.1 Required Runtime Models

- LiteRT rewrite model:
  - `gemma3-1b-it-int4.litertlm` from `litert-community/Gemma3-1B-IT`.
  - Download strategy must prefer a configured public mirror URL (non-gated) and only then use canonical source as fallback.
- Moonshine ASR model pack:
  - `medium-streaming-en` artifacts (adapter/cross_kv/decoder_kv/encoder/frontend/config/tokenizer).

### 4.2 Download and Integrity Rules

- Downloads must run on a dedicated background executor.
- Download result must be typed:
  - success / already available
  - HTTP error
  - hash mismatch
  - size mismatch
  - network/storage/unknown/invalid-spec errors
- Integrity validation requirements:
  - expected size checks when available
  - strict SHA-256 validation when hash exists
  - hash marker + in-memory verification cache for fast checks
- Invalid/corrupted local model file must be rejected and cleaned before reuse.

### 4.3 Update Check Rules

- Update checks must compare remote metadata (ETag, Last-Modified, Content-Length).
- If remote sources are unreachable, operation must return an explicit unreachable state.
- When updates are found and applied, cached remote snapshot must be updated.

## 5. IME UI Requirements

### 5.1 Container and Layout

- IME UI must render in a fixed black bar area.
- Content must be centered within IME space.
- Keyboard must be non-fullscreen (`onEvaluateFullscreenMode = false`).

### 5.2 Pill States

- Idle state:
  - thin rounded gray pill
  - tap starts recording
  - edit icon visible only when current input text is non-empty
  - debug icon always visible; active state means inline debug footer is enabled
- Recording state:
  - expanded dark rounded pill
  - animated white rounded bars in center
  - delete icon on left
  - send icon on right
- Processing state:
  - icons hidden
  - bars morph to loading dots animation
  - status label with stage and elapsed timer
  - stage labels: `Transcribing`, then `Rewriting`

### 5.3 Interaction Gating

- While recording or processing:
  - starting a new recording must be blocked
  - edit action must be blocked
- While processing:
  - output commit must happen only after pipeline completion
  - no intermediate text may be committed

## 6. Audio and Transcription Requirements

### 6.1 Recorder

- Must capture mono PCM16 at 16 kHz.
- Must emit smoothed audio level for UI animation.
- Must stream captured frames to ASR ingest callback.
- Must return full PCM snapshot on stop.

### 6.2 Moonshine Runtime

- Use Moonshine medium-streaming architecture.
- Keep a single native transcriber and one active stream session.
- Transcription strategy:
  - finalize streaming transcript first
  - if empty, run one-shot on full PCM
  - if still empty, reinitialize Moonshine once and retry one-shot
- Must support cancellation and release without leaking stream handles.

## 7. Rewrite and Edit Requirements (LiteRT)

### 7.1 General Rewrite Path (new message)

- If transcript is non-empty and LiteRT model is available:
  - run rewrite with deterministic decoding settings
  - apply cleanup and safety checks
- If rewrite fails:
  - commit original transcript (fallback behavior).
- If LiteRT model is unavailable:
  - bypass rewrite and commit transcript as-is.

### 7.2 Per-message Rewrite Preferences

- Intro directives in transcript must affect rewrite behavior.
- Supported directive families:
  - short/concise/brief
  - warm/friendly/kind
  - work/professional/formal/business
- Directive parsing must support both explicit tags/prefixes and natural language intro forms.

### 7.3 Edit Mode Behavior

- Edit mode requires existing input text.
- LiteRT availability is required only for non-deterministic edit instructions.
- Edit flow must send:
  - current full input text
  - transcribed spoken edit instruction
- Deterministic local command lane must run before LiteRT with strict command-gate:
  - instruction words `<= 10`
  - instruction chars `<= 96`
  - exactly one actionable command verb group
  - explicit target required for target-based commands
  - ambiguous pronoun targets (`it`, `that`, `this`, `thing`, `part`) rejected from local lane
- Deterministic command matrix:
  - `CLEAR_ALL`: verbs `delete|clear|erase|wipe|remove|reset|start over|scratch`
  - `DELETE_TERM`: verbs `delete|remove|erase|drop|cut|take out|get rid of`
  - `REPLACE_TERM`: verbs `replace|change|swap|substitute|use Y instead of X`
- Deterministic scope support:
  - default unscoped operation: `ALL`
  - scoped modifiers: `FIRST` (`first`, `only first`) and `LAST` (`last`, `final`)
- Deterministic target matching requirements:
  - case-insensitive
  - single-token targets use word boundaries
  - multi-word targets use escaped phrase match
  - straight and smart quotes supported
- Deterministic no-match policy:
  - if command is recognized but no match is found in source text, fallback to LiteRT edit
  - if LiteRT fails after fallback, keep original input unchanged
- For non-deterministic edits, LiteRT must return the full final edited message.
- IME must replace current input with the final edited message (local rule output or LiteRT output).

### 7.4 Edit Intent Handling

- Instruction analysis must classify intent:
  - `DELETE_ALL`
  - `REPLACE`
  - `GENERAL`
- Correction phrases must prioritize final instruction intent.
  - Example: `replace X with Y no, make it Z` resolves to `replace X with Z`.
- `DELETE_ALL` must allow blank LiteRT output as a valid final result.
- Non-delete intents must treat blank output as failure/fallback.

### 7.5 List Formatting Feasibility

- List-likeness heuristics must be reused for rewrite and edit.
- Heuristics must consider:
  - existing bullet/numbered structure
  - list cue words
  - shopping/task intent with delimited items
  - delimiter density and short-item patterns
- When list mode is active, prompt must request bullet formatting with `- `.

### 7.6 LiteRT Conservative Rewrite Contract

- Rewrite contract is `edit, do not summarize`.
- LiteRT must:
  - remove disfluencies and obvious repairs conservatively
  - preserve lexical structure unless clearly incorrect
  - never add out-of-context context, social filler, invented actions, or synthetic closings
  - preserve numbers, links, and negation
- Intro-guideline intensity policy:
  - apply intro preferences conservatively by default
  - allow stronger transforms only if explicit high-intensity terms are present
  - high-intensity terms: `very`, `extremely`, `heavily`, `drastically`, `significantly`, `major rewrite`, `substantially`

## 8. Commit Semantics and Session Safety

- Final commit logic must run from `postSendResult(...)` only.
- Session guard must validate current session before commit to prevent stale pastes.
- Compose-new mode:
  - commit only non-empty final output
  - use retry window for `commitText` failures
- Edit mode:
  - replace full current input on success
  - if final output is empty, replace with empty string (clear input)

## 9. Lifecycle, Threading, and Cancellation

- Main thread responsibilities:
  - UI state and final commit operations.
- Background execution:
  - single-thread executor for pipeline
  - single-thread executor for Moonshine chunk/session tasks
- Teardown behavior:
  - cancel in-flight work on input/session finish
  - cancel active ASR/LiteRT operations
  - release recorder/transcriber/engine safely off main thread

## 10. Diagnostics and Observability

- IME must store and expose last message debug metrics.
- Debug payload must include:
  - timing breakdown (total/transcribe/rewrite/chunk waits/finalize/one-shot)

## 11. LiteRT Stability Review Checklist

- Runtime guardrails must be memory-aware and automatic (no user tuning required):
  - runtime tier `LOW/MEDIUM/HIGH` from `memoryClass`, `isLowRamDevice`, and `availMem`
  - hard memory guard skips LiteRT when `lowMemory=true` or very low available memory
- Runtime limits must be surfaced in debug output:
  - effective engine token cap
  - effective rewrite/edit input limits
  - memory snapshot (`availMemMb`, `lowMemory`)
- Native hard-abort marker must be tracked:
  - mark before generation starts
  - clear on normal finish
  - detect stale marker on next startup and expose suspected-abort count
- Model identity must be strict for LiteRT:
  - pinned checksum in catalog
  - strict verification required for readiness and runtime use
  - checksum mismatch must force re-download path
- Fallback reason taxonomy must clearly separate:
  - `TIMEOUT` / `INVALID_ARGUMENT`
  - `MEMORY_GUARD`
  - `RUNTIME_TIER_LIMIT`
  - `COMPATIBILITY_DISABLED` / `ENGINE_INIT_FAILED`
  - transcription path
  - rewrite attempted/applied/fallback reason
  - committed flag
  - edit intent classification
  - list-format hint usage
  - blank-edit-commit-path flag
  - deterministic local-rule diagnostics:
    - `local_rule_detected`
    - `local_rule_kind`
    - `local_rule_scope`
    - `local_matches`
    - `local_no_match_fallback_litert`
- When inline debug is enabled, append a formatted debug footer at the end of committed output.

## 11. Acceptance Requirements

- Edit use case: `delete all` clears existing input reliably.
- Edit use case: `replace X with Y` updates existing message via full LiteRT edit output.
- Correction use case: `X no, Y` applies final intent (`Y`).
- Processing use case: no text is committed before transcription and rewrite/edit stages complete.
- Non-edit fallback use case: if LiteRT rewrite fails, transcript is still committed.
- List use case: list-like text is formatted as bullets more consistently than plain prose.

## 12. Current Test Expectations

- Unit tests must cover:
  - rewrite timeout/invalid-argument policy behavior
  - edit intent classification
  - correction normalization
  - blank-output allow/deny by edit intent
  - list-likeness heuristics
- Manual validation must cover:
  - setup flow, permission flow, model downloads, update check
  - IME idle/recording/processing transitions
  - compose-new and edit-mode end-to-end behavior
