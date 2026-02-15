# Architecture Notes

## System View

- Setup app prepares permissions and models.
- IME handles runtime capture, transcription, optional rewrite/edit, and commit.
- Model layer provides download, validation, and update metadata checks.

## Runtime Pipeline

`IME tap -> AudioRecord -> MoonshineTranscriber -> LiteRtSummarizer (optional) -> commitText`

Details:

1. Audio frames stream to Moonshine while recording.
2. On send, IME stops recorder and waits for pending frame ingestion.
3. Moonshine finalizes streaming transcript.
4. If streaming output is empty, one-shot Moonshine fallback runs.
5. Compose mode can rewrite transcript via LiteRT.
6. Edit mode runs local deterministic rules first, then LiteRT if needed.
7. IME commits only if session/package checks still match.

## Threading Model

- Main thread:
  - IME lifecycle callbacks
  - Compose UI state updates
  - final commit to `InputConnection`
- `executor` (single thread):
  - main send pipeline
- `chunkExecutor` (single thread):
  - Moonshine stream start/frame/finalize tasks

## Key Runtime Guards

- Session id + package guard before final commit.
- Commit retry window for transient `commitText` failures.
- LiteRT runtime profile limits by device memory tier.
- Memory-pressure bypass for LiteRT to avoid instability.
- Native hard-abort marker around LiteRT generation.

## Model Integrity

`ModelStore` validates model artifacts using:

1. expected file size (when provided)
2. marker/cache fast path
3. strict SHA-256 (when configured)

`ModelDownloader` uses temp files and typed result statuses for UI/error handling.
