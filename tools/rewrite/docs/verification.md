# Runtime verification

Verified on September 8, 2026, on Apple Silicon and macOS 26.5.2. Built for macOS 14+; an actual macOS 14 machine was not available.

## Keyboard flow

Select text, press Option-R, then Option-1 through Option-6 to choose Fix grammar, Make clearer, Make shorter, Professional, Casual, or Friendly. The six actions share one native menu, without tone submenus. Number shortcuts belong to that menu, so they do not take over typing in other apps. Previous Option-Shift-R preferences resolve to Option-R; other custom shortcuts are preserved.

The automatic selection toolbar, background selection polling, and result/Copy window have been removed. A successful request directly replaces the captured selection. While processing, the menu-bar icon has a small upper-right dot and its menu shows Rewriting, the action, and Cancel Rewrite. Errors remain in the menu bar with an orange dot, a heading, and wrapped instructions. They never open a result window or retain a result for copying.

## Checks

- All 53 offline checks pass and cover request encoding, Pi auth/model/rewrite subprocess integration, isolated configuration and credential cleanup, model migration, strict completion parsing, subprocess cancellation/timeouts, output limits, and child cleanup. The executable Pi fixture validates stdin and isolation without inference.
- `tests/run.sh --pi-check` passes against Pi 0.85.1 and checks the installed Pi's model discovery in a disposable configuration with a fake credential; it makes no provider inference call.
- `tests/feedback.sh` passes busy/idle/error states, disabled re-entry, cancellation dispatch, no new error window, shortcut migration, Carbon registration/conflict/callback, and all six native Option-number key equivalents (including Option-generated characters).
- A live AppKit popup was opened from the production `ActionMenu` in a test window. Computer use pressed Option-1; the menu closed and the grammar callback assertion passed. This tests menu tracking in addition to calling `performKeyEquivalent` directly.
- The optimized native bundle builds and its signature verifies. The selection integration executable also compiles after removal of the result window.
- Earlier on September 8, a real local Ollama rewrite automatically changed the disposable TextEdit sentence to `She went to the library yesterday.` through the production replacement method. Native Command-Z restored the original. Clipboard types, bytes, item order, and change count were unchanged.
- The same replacement code rejected an app switch and a changed selected range, preserving the source and clipboard. This change keeps that delivery behavior and moves its error messages into the menu bar.

After signing in to Pi, live Luna inference passed on a 926-word rewrite with an isolated configuration and a benchmark-only priority-tier hook. Three Pi samples completed successfully; see [the Pi/Codex benchmark](benchmarks/2026-09-08/README.md). This verifies live CLI inference, not the complete native keyboard-to-replacement path with Pi. Anthropic live inference remains unverified. Native Undo is controlled by the destination app. Locally signed updates can require refreshing Accessibility permission.

## Provider and app compatibility

Rewrite now uses only Pi (updated to 0.85.1). OpenAI uses `openai-codex` as Pi's provider ID; this is a connection inside Pi, not execution of Codex CLI. Anthropic uses Pi's `anthropic` provider. Local inference and the old CLI adapters/fixtures were removed. Earlier Codex/Claude/Ollama results do not establish live Pi compatibility.

TextEdit's targeted AX replacement and native Undo work. Previously tested Microsoft Edge textarea and contenteditable fields exposed readable selections but claimed AX write support without applying the write. Rewrite detects this and now reports it in the menu bar. Browser/custom-editor behavior was not newly tested. No clipboard or paste-keystroke fallback was added.

## Reproduce

```sh
./tests/run.sh
./tests/feedback.sh
./tests/feedback.sh --menu
# Press Option-1 in the test popup.

# Select exactly this disposable sentence in TextEdit:
# She go to the library yesterday.
./tests/selection.sh --app com.apple.TextEdit --automatic
# Requires Pi signed in to OpenAI. Add --anthropic to test Anthropic.
# Then press Command-Z in TextEdit to verify native Undo.

./tests/selection.sh --app com.apple.TextEdit --background
./tests/selection.sh --app com.apple.TextEdit --changed
# Select just library when prompted, within 30 seconds.
```

## Limits

Rewrite reads the foreground selection only when invoked. Text is sent to a processor only after a style is chosen. There is no clipboard mutation, password-field support, rich-style transfer, or guarantee that every app exposes usable selection, replacement, or Undo behavior. Changed selections, background apps, and unsupported writes produce a menu-bar error. macOS has no cross-process atomic compare-and-replace API; Rewrite revalidates immediately before a targeted write and verifies the result without retrying a mutation.

## Reasoning off and priority

The installed app now passes `--thinking off` for both providers. Its sole explicit OpenAI request hook sets `reasoning.effort` to `none` and requests the `priority` tier; no priority fields are sent to Anthropic. The fixture executes the actual JavaScript hook and checks that it preserves the input/model while replacing reasoning and tier fields. A production `ProcessorService` live Luna grammar rewrite passed with these settings. Historical timing benchmarks above used low reasoning and should not be treated as timings for this new configuration. Backend-served tier acknowledgment was not captured.
