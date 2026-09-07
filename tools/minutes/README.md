# Minutes

A small native macOS meeting recorder. **⌥⇧M** starts recording microphone and system audio; the same shortcut stops. Moonshine then transcribes locally, your chosen processor writes the note, and Minutes notifies you when it is ready.

Notes lead with the outcome, followed by decisions, checkable next steps, and open questions when there are any. Search recent meetings, select one, **Copy** the note or **View transcript**. Edit the title or note directly; changes save automatically. Click an action’s checkbox to mark it done. The **…** menu opens saved files or deletes a meeting and its recordings.

## Install

Requires **macOS 15+**, Xcode Command Line Tools, and **Python 3.10+** (`brew install python` if needed).

```sh
curl -fsSL https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/tools/minutes/install.sh | sh
```

Installs `~/Applications/Minutes.app`, a private Python runtime, and the English Moonshine Base model (about 135 MB of model files). Quit Minutes before updating. Saved meetings and settings are preserved. Python packages and model files are downloaded during setup; recordings are never uploaded for transcription.

On first use, choose a processor in Settings. Allow **Microphone** and **Screen & System Audio Recording** in macOS Privacy & Security, then reopen Minutes if macOS asks. No video or screen images are saved. Enable notifications to receive ready alerts. Keep Minutes open in the menu bar; closing its window does not quit it.

## Choose a processor once

- **Local model · Ollama:** install [Ollama](https://ollama.com), run `ollama pull qwen3:8b`, and keep Ollama running. Enter the installed model name in Settings. Minutes contacts only `127.0.0.1:11434`, bypasses HTTP proxies, and rejects models with remote backing. For additional enforcement, start Ollama with `OLLAMA_NO_CLOUD=1 ollama serve`. Model downloads need internet; transcription and note generation then run on this Mac.
- **Codex CLI:** install and sign in to a current `codex`. Minutes uses `codex exec`, stdin, a JSON output schema, an ephemeral run, and a read-only sandbox; user configuration and shell/multi-agent tools are disabled.
- **Claude CLI:** install and sign in to a current `claude`. Minutes uses `--print`, structured output, safe mode, disabled tools/MCP, and no session persistence.

**Codex and Claude may send transcripts to remote services.** Their account, billing, and data policies apply. Minutes labels them separately from Local. Nothing is sent until you stop a recording or explicitly retry it with the selected provider. CLI executables are discovered in the inherited PATH, Homebrew, `/usr/local/bin`, and `~/.local/bin`.

The editorial brief is “capture outcomes, remove repetition, and preserve uncertainty.” Transcripts are untrusted source material, never processor instructions. Proposals must remain proposals; owners and deadlines appear only when stated. Models can still make mistakes, so small corrections are available directly in the note.

## Saved work and recovery

Everything is under `~/Library/Application Support/Minutes/`. Each meeting has its own directory with metadata, timestamped microphone/system CAF files, transcription checkpoints, a complete `transcript.txt`, and a portable `note.txt`. Files are private to your macOS user, **not separately encrypted**. Recordings remain until you delete the meeting; disk usage can be several hundred MB per hour depending on device format.

Audio writes to disk in segments of at most about a minute. Transcription starts only after capture stops, processes bounded segments, and checkpoints each one. Long transcripts are condensed in cached stages rather than truncated. A failed provider never removes the source recording or transcript. **Retry** reuses completed transcription and matching summary checkpoints, using the current processor setting. Opening a meeting interrupted by an app restart offers recovery. A force quit can leave the final audio segment incomplete; completed segments remain preserved. Errors include access to the original files and processing log via **… → Open saved files**.

## Development

```sh
cd tools/minutes
./setup.sh                 # once: isolated runtime + Moonshine model
./build.sh                 # signed app bundle, no Xcode project
open build/Minutes.app
./tests/run.sh             # persistence, audio buffers, recovery, pipeline rules
```

To install a local build after quitting Minutes:

```sh
mkdir -p ~/Applications
ditto build/Minutes.app ~/Applications/Minutes.app
open ~/Applications/Minutes.app
```

For an isolated visual review with sample data:

```sh
python3 tests/review.py /tmp/minutes-review
open build/Minutes.app --args --review --data-dir /tmp/minutes-review
```

Review mode uses a separate settings/meetings directory and suppresses notifications. It does not install a second runtime. To record in that profile, run `MINUTES_SUPPORT=/tmp/minutes-review ./setup.sh` first. Never point review mode at your normal Minutes directory.

Ownership is explicit: `Recorder.swift` owns ScreenCaptureKit and serial audio writes; `Meeting.swift` owns storage; `MinutesModel.swift` owns workflow; `MinutesView.swift` owns native views; `Minutes.swift` wires the app, shortcut, status item, and notifications. `Resources/worker.py` owns post-recording transcription and processors. There are no dependencies on other tools in this repository.

## Practical limits

English transcription, one meeting at a time, and no speaker diarization: **Microphone/System are audio sources, not people**. All eligible system audio is captured, including other apps’ sounds. Headphones reduce duplicate speech from speaker echo. Protected audio may be unavailable. Permission changes, device changes, sleep, or capture failures may interrupt recording; Minutes preserves available files and surfaces an error. The app prevents idle sleep while working, but cannot prevent lid-close or forced sleep.

The 60-second segment boundary can reduce transcription accuracy for a word crossing it. Long notes depend on the chosen model’s quality and may lose nuance during staged condensation. Current CLI versions are required; older versions may not support the isolation flags. This is an ad-hoc signed local build, not a notarized distribution; updates may require macOS to reapprove capture access.

See [verification notes](docs/verification.md) for tested behavior and remaining runtime gaps.

Interfaces checked against [Apple ScreenCaptureKit](https://developer.apple.com/documentation/screencapturekit), [Moonshine’s official Python example](https://github.com/moonshine-ai/moonshine/blob/main/examples/python/basic_transcription.py), [Ollama Chat](https://docs.ollama.com/api/chat), [Codex noninteractive mode](https://developers.openai.com/codex/noninteractive/), and the installed `codex exec --help` / `claude --help`.
