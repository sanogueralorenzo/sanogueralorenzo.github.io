# Minutes

A small macOS app that turns meetings into a recap, decisions, next steps, and open questions.

**Install or update** from the latest `main` (macOS 15+, Xcode Command Line Tools, and Python 3.10+):

```sh
curl -fsSL https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/tools/minutes/install.sh | sh
```

Installs in `~/Applications` with an English Moonshine transcription model. Quit Minutes before updating; saved meetings are preserved.

Install Pi separately, then run it and use `/login`:

```sh
npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest
pi
```

Choose **Provider → OpenAI · Luna** (default, no reasoning) or **Anthropic · Haiku** (thinking off). Existing Local users must choose a provider before continuing. Transcription stays on this Mac; the transcript goes to your chosen provider through Pi to write the note.

When recording permissions are missing, click **Grant Permissions** in the menu bar dropdown or the window’s bottom banner. Allow **Microphone** and **Screen & System Audio Recording** when prompted or in macOS Privacy & Security. If both are missing, allow microphone access first, then click **Grant Permissions** again if needed for screen/system audio access. The buttons disappear once both are allowed. Reopen Minutes if macOS asks. Updates may require permission again.

Press **⌥⇧M** to start recording microphone and system audio, and again to stop. Minutes transcribes after recording and notifies you when the note is ready. Headphones reduce echo; no video is saved. Keep the app running in the menu bar while it finishes.

Search meetings, edit notes directly, check off actions, **Copy**, or **View transcript**. Changes save automatically. **Retry** resumes saved work; **… → Export note** saves the current note as a text file; **Delete meeting** removes its saved note, transcript, and recordings. Existing `note.txt` files are retained as snapshots; edits now save only to the authoritative meeting record.

Meetings stay in `~/Library/Application Support/Minutes/` until deleted. English only; Microphone/System identify audio sources, not speakers. Check the note against the transcript when accuracy matters.

Local build: `./build.sh` · Core checks: `./tests/run.sh` · [Validation and remaining gaps](docs/verification.md).
