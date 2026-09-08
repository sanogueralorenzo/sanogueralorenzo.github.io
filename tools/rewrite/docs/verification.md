# Runtime verification

Verified on September 8, 2026, on Apple Silicon and macOS 26.5.2. Built for macOS 14+; an actual macOS 14 machine was not available.

## Automatic replacement and menu-bar progress

Choosing an action now runs the model in the background and directly applies its result through the captured Accessibility element. Successful requests show no preview or acceptance dialog. A dot appears in the upper-right of the menu-bar icon until delivery finishes, fails, or is cancelled. The menu shows `Rewriting…` and the action, disables starting a second rewrite, and offers Cancel Rewrite. Escape and the existing shortcut also cancel an active request.

| Check | Evidence |
| --- | --- |
| Build and signature | Optimized native bundle compiles; `plutil`, signature verification, and diff whitespace checks pass. |
| Offline processor tests | All 36 focused checks pass, covering request encoding, model resolution, parsing, local-model restrictions, subprocess cancellation/timeouts, output limits, and child cleanup. |
| Busy indicator and menu | `tests/feedback.sh` verifies idle/busy/reset state, action text, disabled re-entry, menu cancellation dispatch, and that the dot does not intercept clicks. The rendered icon has a small upper-right dot. |
| Failure/Copy notice | Native test verifies Copy availability only with a generated result, Close dispatch, and absence of a Replace button. The real AppKit window was inspected through computer use; its message, text, Close, and Copy controls are legible. View-only bitmap capture does not accurately composite the native button labels, so that bitmap is not the visual reference. |
| Real automatic delivery | `tests/selection.sh --app com.apple.TextEdit --automatic` used an existing local Ollama model to rewrite the disposable sentence, then called production replacement with `requireForeground: true`, without an acceptance step. The visible source became `She went to the library yesterday.` |
| Undo and clipboard | Native Command-Z restored `She go to the library yesterday.` after automatic delivery. The integration test confirmed unchanged clipboard types, bytes, item order, and change count. |
| App switch | `--background` puts the test notice in front, attempts automatic replacement, and verifies rejection with the original source unchanged. Automatic delivery never activates a background source app. |
| Changed selection | `--changed` captured the sentence, then computer use selected just `library`. The production replacement path rejected the stale selection and left the source and clipboard unchanged. |
| Toolbar | Native rendering, all six action callbacks, dismissal, screen-edge placement, and clipboard checks pass. Earlier on September 8, the production foreground watcher also passed live TextEdit detection, unchanged focus, selection-change invalidation, disabled-state suppression, and no resurfacing after dismissal. |
| Shortcut | Carbon registration, duplicate-shortcut rejection, and callback dispatch pass in the feedback test. |

The automatic-delivery integration test composes the production processor, status item, and replacement code. A physical click through the packaged app with every provider has not been verified. The installed app was not replaced by this change. Local rebuilds can require the user to re-enable Accessibility; no permission settings were changed. The temporarily started loopback Ollama server was stopped after the live test.

## Previously verified processor and app compatibility

On September 7, Codex CLI 0.153.2 completed a real isolated grammar request. Claude CLI 2.1.179 exposed the required flags, but its existing OAuth token was expired; successful Claude inference remains unverified without signing in again. Ollama 0.33.3 with qwen3:8b completed a real request. The loopback protocol fixture passed three discovery/chat/local-only checks.

TextEdit's targeted AX replacement and native Undo work. Previously tested Microsoft Edge textarea and contenteditable fields exposed readable selections but claimed AX write support without applying the write; Rewrite detected this and offered Copy. Browser/custom-editor behavior was not newly tested for this change. No paste-keystroke fallback was added.

## Reproduce

```sh
./tests/run.sh
./tests/feedback.sh
./tests/toolbar.sh

# Select exactly this disposable sentence in TextEdit:
# She go to the library yesterday.
./tests/selection.sh --app com.apple.TextEdit --automatic
# Requires running local Ollama with an existing downloaded text model.
# Then press Command-Z in TextEdit to verify native Undo.

./tests/selection.sh --app com.apple.TextEdit --background
./tests/selection.sh --app com.apple.TextEdit --changed
# Select just library when prompted, within 30 seconds.

./tests/toolbar.sh --selection --foreground --changed
# Select just library when prompted, within 30 seconds.
```

## Limits

Automatic detection reads the foreground selection locally about every 350 ms while enabled and idle, waits for two matching samples, and pauses during mouse gestures/modifier-key selection. Text is sent to a processor only after an action is chosen. There is no clipboard mutation on capture or replacement, no password-field support, no rich-style transfer, and no guarantee that every app exposes usable selection, replacement, or Undo behavior. Unreadable selections are ignored by the automatic toolbar; explicit invocation explains the limitation. Changed selections, background apps, and unsupported writes preserve the generated result for Copy. macOS has no cross-process atomic compare-and-replace API; Rewrite revalidates immediately before a targeted write and verifies the result without retrying a mutation.
