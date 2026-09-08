# Runtime verification

## Automatic selection toolbar — September 8, 2026

The optimized bundle builds and its signature verifies. All 36 focused checks and the existing native preview/shortcut checks pass. The production toolbar was rendered and visually inspected: all six labeled actions fit, dispatch the correct edit, and remain within each available screen’s visible bounds. Its panel cannot become key or main.

`tests/toolbar.sh --selection --foreground --changed` passed against a disposable TextEdit document using the production foreground capture and timer. It verified automatic appearance after a stable selection, no foreground-focus change, an unchanged clipboard, a safely replaceable capture, dismissal without resurfacing, a new toolbar after selecting a different range, permanent invalidation of the old capture, and suppression while disabled. The same test also supports targeting TextEdit directly by omitting `--foreground`, useful when the automation surface operates in the background. The `--changed` stage asks the tester to select just `library` within 30 seconds.

The production AX replacement integration check passed again in TextEdit; native Command-Z restored the source sentence. The native preview check verifies Return/Escape and disabled replacement, and the toolbar’s six callbacks share the existing `Rewrite.run` processing/preview path. No fresh provider inference was run for this UI change.

The packaged build launched, but computer-use inspection timed out twice, so a physical toolbar-click → provider → preview → Replace sequence in that bundle remains unverified. The previously installed app was restored after the smoke test; no Accessibility permissions were changed. Locally signed builds can require the user to re-enable Accessibility. Browser/custom-editor and actual macOS 14 toolbar behavior were not newly tested.

The toolbar reads the foreground selection locally about every 350 ms while enabled and idle, requires two matching samples, and pauses during mouse gestures/modifier-key selection. It does not send text to a processor until an action is chosen. Outside clicks, typing, scrolling, Escape, the close control, app/field/selection changes, Settings, and active requests hide or suppress it. Some apps expose no selection, incomplete geometry, or no safe replacement; the existing shortcut and Copy fallbacks remain available.

Verified on September 7, 2026, on Apple Silicon, macOS 26.5.2, Swift 6.3.3. Built for macOS 14+. The macOS 14 deployment target was compiled; an actual macOS 14 machine was not available.

| Check | Result |
| --- | --- |
| Build and signature | Optimized native bundle compiles; `plutil`, `codesign --verify --deep --strict`, and shell syntax checks pass. |
| Offline tests | 27 checks: JSON source isolation, six actions, whitespace, UTF-16/emoji ranges, stale fingerprints, response parsing, tool-result rejection, local/cloud metadata, stdin, stderr disposal, output limits, timeout, cancellation, and child-process cleanup. |
| Codex CLI 0.153.2 | Installed help verified. A real isolated grammar request passed, including after moving request state/logs out of the shared authentication store. |
| Claude CLI 2.1.179 | Installed help verified. Existing sign-in is present, but a real request returned an expired OAuth token. Rewrite maps this to specific `/login` guidance. Successful Claude inference could not be verified without signing in again. |
| Ollama 0.33.3 / qwen3:8b | The existing loopback service returned a real corrected sentence. No download or service configuration change was needed. |
| Local protocol fixture | Three HTTP checks pass against a separate fixture on port 11435: discovery excludes cloud entries, chat contains only editing rules and the encoded selection, and renamed cloud models are refused. This fixture is not inference. |
| TextEdit rich-text document | Captured the exact selected sentence; replaced through `AXSelectedText`; verified the complete resulting value and source focus. Native ⌘Z restored the original. Clipboard types, bytes, item order, and change count were identical before and after. |
| Selection changes | Moving the TextEdit selection while a captured request was pending invalidated replacement. The clipboard stayed identical. |
| Microsoft Edge text area | Capture and UTF-16 range succeeded. Edge claimed AX replacement support but did not apply the write. Rewrite detected this and kept the source unchanged with Copy guidance. |
| Microsoft Edge contenteditable | Same capture success and safe Copy fallback; original value and clipboard remained unchanged. |
| Native preview | Production `Preview` renders; Return invokes Replace, Escape cancels both processing and preview, and Return cannot bypass a disabled Replace button. The preview contracts for a short result. |
| Shortcut | Carbon registration, duplicate-shortcut rejection, and hotkey callback dispatch pass. Native menu navigation is provided by `NSMenu`. |
| First launch | The native processor/model/shortcut settings window and discovery state were inspected through Accessibility. |

The selection integration test calls production selection code against a named running app. It accepts only the exact disposable sentence `She go to the library yesterday.` so it cannot accidentally rewrite another document. UI automation prepares the fixtures and verifies the visible TextEdit result and Undo. Preview and key handling are exercised by an AppKit test process using the production views.

The computer-use service repeatedly timed out when reconnecting to the newly built app, although it could inspect first launch and operate TextEdit and Edge. Therefore a physical global-key → menu → preview → Return sequence in the installed menu-bar app was not fully verified by that service. The individual production paths above were verified without bypassing macOS permission settings. The installed app still requires the user to enable Accessibility, and a locally signed rebuild can require re-enabling that permission.

Reproduce:

```sh
./tests/run.sh
./tests/preview.sh
./tests/run.sh --live codex
./tests/run.sh --live claude   # requires a currently valid sign-in
./tests/run.sh --live ollama

# Prepare the exact disposable sentence in TextEdit, select it, then:
./tests/selection.sh --app com.apple.TextEdit --replace
# Press Command-Z in TextEdit to check native Undo.
./tests/selection.sh --app com.apple.TextEdit --changed
# Move the selection within five seconds.

# Serve tests/browser.html on loopback; select its fixture in Edge:
./tests/selection.sh --app com.microsoft.edgemac --copy-only

# In a separate terminal; uses 11435 and leaves real Ollama alone:
python3 tests/ollama_fixture.py
./tests/run.sh --ollama-fixture
```

Concrete limits: no blind copy/paste fallback, no password fields, no rich-style transfer, and no guarantee that every app exposes a usable selection or implements AX replacement/Undo. Browser read-only selections and custom editors can be copy-only or unreadable. Only loopback Ollama is supported. Very long selections are rejected; local requests also reserve context for the output. macOS provides no atomic compare-and-replace API across processes, so Rewrite revalidates immediately before a targeted write and verifies its result. It never restores a stale range or sends a paste to the foreground app.
