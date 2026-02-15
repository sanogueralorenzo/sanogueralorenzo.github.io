# Voice Keyboard Requirements

This file is intentionally short. It captures the product constraints and invariants that should not drift.

## Product Boundaries

- Android custom keyboard (IME) plus setup app.
- On-device transcription and on-device rewrite/edit.
- No cloud inference for core runtime flow.
- Network is allowed only for model download and update checks.

## Core User Flow

1. User records from the IME.
2. Audio is transcribed locally.
3. Transcript is rewritten or edited locally when configured.
4. Final text is committed to the active input field.

## Required Runtime Components

- `VoiceInputMethodService` for lifecycle and orchestration.
- `VoiceAudioRecorder` for 16kHz mono PCM capture.
- `MoonshineTranscriber` for ASR.
- `LiteRtSummarizer` for rewrite/edit.
- `ModelCatalog`, `ModelDownloader`, `ModelStore`, `ModelUpdateChecker` for model lifecycle.

## Rewrite and Edit Behavior

- Compose mode:
  - run LiteRT rewrite only when enabled and model is available
  - if rewrite fails, commit raw transcript
- Edit mode:
  - deterministic local commands run first
  - local no-match can fall back to LiteRT edit
  - if LiteRT edit fails, keep original text

Deterministic local command families:

- clear all
- delete term (all/first/last)
- replace term (all/first/last)

## Safety and Reliability Invariants

- Final commit must be session-safe (no stale paste into another field/app).
- Cancellation must stop in-flight recording/transcription/rewrite work.
- LiteRT failures must degrade gracefully to non-destructive output.
- Model files must pass size validation, and SHA validation when hash is configured.
- Corrupt model files must not be reused.

## Setup App Expectations

- Can request microphone permission.
- Can open IME settings and IME picker.
- Can download required models and show progress.
- Can check model updates.
- Can toggle LiteRT rewrite and persist custom rewrite instructions.

## Diagnostics

- IME exposes per-send debug metrics (latency, path, fallback reason, rewrite metadata).
- Model and runtime failures should be visible in logs and actionable in setup UI.

## Definition of Done

- `./gradlew :app:compileDebugKotlin` passes.
- Unit tests pass.
- Core IME flow works on device:
  - record -> transcribe -> rewrite/edit -> commit
  - graceful fallback behavior is preserved.
