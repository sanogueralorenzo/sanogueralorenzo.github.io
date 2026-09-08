# Verification

8 September 2026 · Apple silicon · macOS 26.5.2 · Pi 0.85.1. Provider checks used only invented speech and generated audio.

`./tests/run.sh` checks provider migration and immediate saving, activity permissions, meeting persistence/recovery/deletion, readable PCM files and lossless 60-second audio rotation, plus Python pipeline checks:

- Both fixed providers use private access-only credentials, disabled tools/context, fresh sessions, and one process per job.
- Partial output, tool calls, crashes, and timeouts fail without publishing a note. Cancellation and job completion remove the process and credentials; long jobs renew credentials between requests.
- Fitting transcripts use one request. Unicode, blank lines, long lines, and all source text survive budgeted splitting.
- Retry reuses valid checkpoints. Cache identity includes the fixed model, system brief, prompt version, synthesis mode, and source.
- Raw transcript input and explicit partial-note synthesis retain strict validation of all five note fields.

Live Luna checks passed before and after shortening the brief: conditional launch dates stayed conditional; explicit owners/deadlines and corrected numbers survived; suggestions did not become commitments; discussion-only notes had empty decision/action arrays. A three-request synthesis retained a later Thursday correction to an earlier Tuesday commitment.

Generated microphone/system audio passed through actual Moonshine inference, the worker, and Luna to a saved note. Transcription confused “Ana” with “Anna” and “owner” with “honor”; the note flagged uncertainty about support ownership. The source transcript remains available for corrections.

Pi's installed catalog reports 272,000 context / 128,000 output tokens for Luna and 200,000 / 64,000 for Haiku. Runtime budgets reserve the full output allowance, system brief, and 8,192 tokens of headroom, conservatively counting each UTF-8 byte as a token. No automatic compaction or source truncation is enabled.

Build, plist, ad-hoc signature, and focused checks pass. The native Provider menu was inspected and selection saved immediately without a sheet. Native Retry completed a synthetic saved transcript through the app, worker, and Pi, returning to idle with an editable note. Bundle signature verification also passed after processing.

Remaining gaps: live Haiku quality is untested because Pi is not signed in to Anthropic; offline checks were explicitly accepted. Live dual-source capture, device unplugging, lid-close interruption, notification delivery, multi-hour recordings, Intel, and macOS 15 still need a permitted test session. A force quit can leave the final CAF incomplete; completed segments and checkpoints remain available. These synthetic quality checks are examples, not an accuracy guarantee.

Run optional synthetic provider checks with `python3 tests/quality.py openai` or `anthropic`. For live capture, use headphones and an invented discussion, verify both audio sources across a minute boundary, then check the transcript, restart recovery, and Retry.
