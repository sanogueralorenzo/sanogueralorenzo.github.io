# Architecture Notes

## Components

- `VoiceInputMethodService`
  - IME lifecycle + orchestration.
  - Owns recording, streaming ASR finalization, rewrite, and final commit.
- `VoiceAudioRecorder`
  - `AudioRecord` capture + audio level callback for UI.
  - Forwards raw PCM frames to Moonshine stream ingestion.
- `MoonshineTranscriber`
  - On-device ASR wrapper for tiny-streaming Moonshine runtime.
  - Supports stream lifecycle and one-shot fallback transcription.
- `LiteRtSummarizer`
  - On-device rewrite engine via LiteRT-LM.
- `ModelStore` / `ModelDownloader`
  - Runtime model presence, verification, and downloads.

## Threading

- Main thread:
  - Compose state/UI and final `InputConnection.commitText`.
- `executor` (single-thread):
  - Main send pipeline (`transcribe -> rewrite -> post result`).
- `chunkExecutor` (single-thread):
  - Moonshine stream start/add-audio/finalize tasks.

## Send Pipeline

1. User taps Send in IME.
2. Service stops recorder and captures full PCM.
3. Service waits for queued Moonshine frame ingestion tasks.
4. Service finalizes Moonshine streaming transcript.
5. If streaming transcript is empty, service runs Moonshine one-shot transcription on full PCM.
6. If LiteRT model is available, transcript is rewritten.
7. Result is committed to current editor if the session is still current.

## Session Safety

The service uses a monotonic session id and package check before committing to avoid
pasting stale text into a different editor after focus/app changes.

## Model Integrity

`ModelStore` uses:

1. Expected file size checks.
2. Fast hash marker + in-memory verified cache.
3. Optional strict SHA-256 computation when required.
