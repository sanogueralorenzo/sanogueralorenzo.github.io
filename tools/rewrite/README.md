# Rewrite

A small native macOS menu for improving selected text. No chat, library, or history.

**Install or update** (macOS 14+ and Xcode Command Line Tools):

```sh
curl -fsSL https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/tools/rewrite/install.sh | sh
```

Installs in `~/Applications`. On first launch, choose a processor and model. Enable Rewrite in **System Settings → Privacy & Security → Accessibility**. The pencil menu provides Settings and Quit. Click the shortcut in Settings to record another combination (include Command, Control, or Option).

Select text and pause briefly: a small toolbar appears beside the selection without taking focus. Click **Fix grammar**, **Make clearer**, **Make shorter**, **Professional**, **Casual**, or **Friendly** directly. Typing, scrolling, clicking outside, Escape, or the toolbar’s × dismisses it. A dismissed selection stays dismissed until the selection changes. Turn this off with **Show rewrite toolbar when text is selected** in Settings.

The keyboard shortcut **⌥⇧R** and **pencil menu → Rewrite Selection** also remain available. In the keyboard menu, choose **Fix grammar**, **Make clearer**, **Make shorter**, or **Change tone → Professional / Casual / Friendly**. Use arrow keys and Return in the native menu. The result appears in a compact preview: **Return** replaces, **Copy** (⌘⇧C) copies, and **Escape** cancels. **Show original** reveals the source for comparison. Escape also cancels processing. Requests time out after 90 seconds.

Processor choices:

| Processor | Setup | Where text goes |
| --- | --- | --- |
| Codex CLI | Install Codex, run `codex login`, then Refresh. Requires a version with `--ignore-user-config` and `--ephemeral`. | OpenAI, using your existing CLI sign-in. |
| Claude CLI | Install Claude Code, sign in through `claude`, then Refresh. Requires `--safe-mode`, `--tools`, and `--no-session-persistence`. | Anthropic, using your existing CLI sign-in. |
| Ollama | Start Ollama and run `ollama pull <model>`. Refresh and select a downloaded text model. | This Mac, through `http://127.0.0.1:11434`. Cloud models and HTTP redirects are rejected. |

CLI discovery checks `~/.local/bin`, Homebrew, inherited PATH, and the bundled Codex executable. Model names can also be entered directly. The model picker starts with **GPT 5.6 Luna · Light reasoning** for Codex and **Claude Haiku 4.5 · Thinking off** for Claude. Codex requests use Light reasoning (`low`), including when selecting another model. Haiku 4.5 requests disable extended thinking (`MAX_THINKING_TOKENS=0`) for quick, economical edits. Previously saved automatic model choices resolve to these named models. Codex's project/user configuration is intentionally not loaded. The existing authentication store stays in place so token refresh works normally. Provider account limits and service-side data policies still apply.

Each request contains the selected text plus editing instructions. Source text is encoded as data and never interpreted by Rewrite as a command. Requests run outside your project. Codex uses an ephemeral session, temporary state/log directories with logging disabled, replacement editing instructions, read-only sandbox, and disabled shell, app, plugin, hook, browser, and other tool features. Claude uses safe mode, an empty tool/MCP set, a replacement system prompt, and no session persistence. Automatic detection reads the foreground app’s exposed selection locally while Rewrite is idle; no processor request is sent until an action is chosen. Rewrite stores only processor, model, shortcut, and toolbar preferences; it does not log text, results, or raw processor errors.

Replacement uses the captured Accessibility element directly. It requires the original field, window, full field value, and UTF-16 selection to still match. Observed text/selection changes permanently invalidate the request. **Capture and Replace never change the clipboard or send a global paste keystroke.** Copy intentionally puts the result on the clipboard. The destination app controls Undo and formatting behavior.

The automatic toolbar requires Accessibility permission and an exposed text selection. It waits for the selection to settle (typically under a second), stays hidden during processing and Settings, and ignores secure, empty, oversized, or unreadable selections. Apps with custom selection handling may require the shortcut or may not work at all.

Some apps expose readable text but cannot safely replace it. Those results remain available to copy. Apps that do not expose selected text (including secure fields, some browser content, terminals, and custom editors) show a short message. There is no blind copy/paste fallback. Selections are limited to 24,000 UTF-16 units; rich styling is not transmitted, but textual structure is preserved. AI edits can still be imperfect: review the result before accepting.

Local development:

```sh
./build.sh                 # build/Rewrite.app, ad-hoc signed
./install.sh --local       # build and install this checkout
./tests/run.sh             # offline focused tests
./tests/run.sh --live codex
./tests/run.sh --live claude
./tests/run.sh --live ollama
./tests/preview.sh         # native layout and keyboard checks
./tests/toolbar.sh         # toolbar layout, action dispatch, and dismissal
./tests/toolbar.sh --selection --changed # live TextEdit selection checks
./tests/selection.sh --app com.apple.TextEdit --replace
```

Live tests send a fixed, disposable grammar example using existing authentication. Selection tests require selecting exactly `She go to the library yesterday.` in a disposable document; they refuse other text. `Rewrite.app/Contents/MacOS/Rewrite --review` adds a Dock presence for inspection and uses the production selection and processing paths. See [runtime verification](docs/verification.md) for tested apps and concrete limitations. Locally signed rebuilds may require re-enabling Accessibility permission.

Interfaces verified against installed CLI help and official references: [Codex noninteractive mode](https://developers.openai.com/codex/noninteractive), [Codex configuration](https://developers.openai.com/codex/config-reference), [Claude CLI](https://code.claude.com/docs/en/cli-reference), [Ollama chat](https://docs.ollama.com/api/chat), and [Ollama model metadata](https://github.com/ollama/ollama/blob/main/api/types.go).
