# Verification

Verified on macOS 26.5.2, Apple silicon, 7 September 2026. Built for macOS 15+. No live meeting or personal transcript was sent to a provider during testing; provider tests used invented discussions and generated speech.

## Automated checks

`./tests/run.sh` passes the Swift checks and nine Python tests:

- Atomic note persistence, corrections, restart recovery, deletion, and hour-long duration formatting.
- Damaged metadata remains visible and its original bytes are preserved.
- Real CoreMedia PCM buffers at 44.1/48 kHz write all expected frames to readable CAF files. Gaps and device changes retain timestamps.
- 122 seconds of continuous synthetic system audio rotates into three bounded segments without losing frames.
- Empty sections omitted, checkbox formatting, rejection of malformed or empty notes.
- Long lines remain intact; failed long-transcript processing reuses completed summary checkpoints on retry.
- Existing transcripts skip transcription; CLI pipes drain and failures surface.
- Cloud model names and custom aliases with remote backing are rejected before transcript submission.

`./build.sh`, shell syntax checks, Python compilation, bundle plist validation, and ad-hoc signature verification pass.

## Runtime and visual checks

- Installed the pinned `moonshine-voice==0.1.5` runtime and downloaded the English Base model. Actual inference on macOS-generated speech produced timestamped text locally. One phrase was misrecognized (“pricing question” → “price in question”), illustrating why the source and corrections remain available.
- Ran the entire worker on two generated microphone/system tracks: Moonshine saved a merged transcript and Codex returned a concise note with an agreed date, an explicitly assigned action/deadline, and an unresolved discount question. No owner was invented for the unresolved issue.
- Real `codex exec` structured output succeeded using the installed CLI’s supported flags.
- Real Ollama requests to a local `qwen3:8b` model succeeded. A proposed launch remained unconfirmed, an explicit owner and relative deadline were retained, and an annual-plan question remained unresolved. A preliminary 0.6B model produced weak notes and is not the recommended model. These examples are smoke checks, not a guarantee of model accuracy.
- Exercised native Retry on a saved transcript through the app → Python worker → local Ollama → saved finished note. The compact processing state appeared and the finished note replaced it.
- Inspected the actual native window in dark mode, including a complete note, recap-only note, search results, transcript sheet, and recoverable error. The sample note’s recap, decisions, action items, and open question fit within the default window.
- Edited a note via the native editor and verified the correction in its JSON on disk and after app restart. Clicked an action checkbox and verified it changed to checked. Search filtered the recent list, and View transcript showed the source text independently of note corrections.
- Verified the final settings sheet visually and confirmed that Cancel discards an unsaved model change; provider settings only apply after Save.

## Remaining verification gaps

- **Live dual-source capture is permission-gated on this Mac.** Starting capture reached the macOS Screen & System Audio Recording denial path and showed the correct permission instructions. Real microphone-plus-meeting-app capture, device unplugging, lid-close interruption, and notification delivery still need a permitted desktop session. Automated PCM tests verify writing and segment behavior, not ScreenCaptureKit’s delivery from each meeting app.
- **Claude’s local OAuth token was expired (401).** Its installed help confirms the implemented flags; the real invocation returned a clear authentication failure. Successful Claude summarization needs the user to sign in again.
- Multi-hour physical recordings, Intel Macs, and the minimum macOS 15 release have not been exercised. Segment and retry behavior were tested with bounded synthetic recordings and oversized text fixtures.
- A force quit can leave the last CAF incomplete. Original recordings and completed checkpoints remain; an unreadable segment may need manual repair/removal through Open saved files before retry. Normal stop finalizes all segments.

For a live acceptance check: use headphones; allow both capture permissions; speak into the microphone while a meeting app plays a distinct spoken sentence; press ⌥⇧M to stop; verify both source labels in the transcript and the outcome in the note. Repeat once across a minute boundary, then check a restart and a failed-provider retry. Use an invented discussion until the capture setup is verified.
