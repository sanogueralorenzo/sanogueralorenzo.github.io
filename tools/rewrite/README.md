# Rewrite

A small native macOS menu for improving selected text. No chat, library, or history.

**Install or update** (macOS 14+ and Xcode Command Line Tools):

```sh
curl -fsSL https://raw.githubusercontent.com/sanogueralorenzo/sanogueralorenzo.github.io/main/tools/rewrite/install.sh | sh
```

Installs in `~/Applications`. On first launch, sign in through Pi, then choose a provider and model. Enable Rewrite in **System Settings → Privacy & Security → Accessibility**. The pencil menu provides Settings and Quit. Click the shortcut in Settings to record another combination (include Command, Control, or Option).

Select text, press **⌥R (Option-R)**, then choose a style with its shortcut:

| Shortcut | Style |
| --- | --- |
| ⌥1 | Fix grammar |
| ⌥2 | Make clearer |
| ⌥3 | Make shorter |
| ⌥4 | Professional |
| ⌥5 | Casual |
| ⌥6 | Friendly |

You can also click a style or use arrow keys and Return. The pencil menu’s **Rewrite Selection** opens the same menu. There is no automatic popup when selecting text.

The result replaces the selected text automatically, without a preview, Replace button, or Copy window. Use **⌘Z** in the source app to undo (Undo support is controlled by that app).

While working, a small dot appears at the upper-right of the pencil menu-bar icon. Open the menu to see **Rewriting…**, the style, and **Cancel Rewrite**. Escape or pressing the Rewrite shortcut again also cancels processing. Errors appear in that menu with an orange dot and instructions; they never open a result window. Requests time out after 90 seconds.

Rewrite always uses the installed **Pi CLI**. It does not launch Codex CLI or Claude CLI, and has no local model option.

Install or update Pi separately, then open it and use `/login`:

```sh
npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest
pi
```

| Provider | Pi sign-in | Initial model |
| --- | --- | --- |
| OpenAI | OpenAI (ChatGPT Plus/Pro) | GPT 5.6 Luna · Reasoning off · Priority |
| Anthropic | Anthropic | Claude Haiku 4.5 · Thinking off |

Selected text goes to the chosen provider through Pi. Codex/Claude CLI credentials are not reused. In Rewrite Settings, click Refresh after signing in. Discovery checks `~/.local/bin`, Homebrew, and inherited PATH for `pi`. Pi and its runtime are not bundled into Rewrite. Requires Pi with `auth check --json --credentials` and the isolation flags below; verified with 0.85.1.

The model picker lists the selected provider's built-in Pi models. Model IDs can also be entered directly, without provider prefixes or reasoning suffixes. Both providers use Pi thinking `off`. For OpenAI, Rewrite explicitly sends `reasoning.effort: "none"` and `service_tier: "priority"` through its own small request hook. Priority is requested, not guaranteed by the backend, and may consume more provider usage. Anthropic receives no OpenAI priority fields. Saved Codex and Claude choices migrate to their corresponding Pi provider. A saved Ollama choice requires choosing a cloud provider in Settings before any text can be sent. Provider account limits and service-side data policies still apply.

Each request contains the selected text plus a short rewrite-only system prompt. Pi also appends the disposable working-directory path. Source text is encoded as JSON data. Pi runs outside your project with `--no-tools`, `--no-extensions`, `--no-skills`, `--no-prompt-templates`, `--no-context-files`, `--no-themes`, `--no-approve`, and `--no-session`. OpenAI requests load only Rewrite’s explicitly supplied priority/reasoning hook; extension discovery remains disabled. The hook is written inside the disposable request directory, registers no tools, and logs no text or credentials. Startup networking is disabled with `--offline`; model inference still uses the network. Automatic compaction and retries are disabled.

Pi's dedicated auth command resolves and refreshes your credential in its normal store. Only that resolved credential enters a private temporary Pi directory (OAuth refresh tokens are not copied), with a mode-600 auth file. Global settings, custom model endpoints, extra system prompts, and sessions are not loaded into the rewrite request. The directory stays private for the lifetime of the RPC process and is removed when it stops; forcibly killing the app or a system crash can prevent cleanup. Tokens are never passed in command arguments or printed by Rewrite. JSON event parsing accepts only a completed assistant response, rejects tool calls and interrupted/truncated responses, and excludes thinking from replacement text.

Rewrite starts Pi in **RPC mode** on the first rewrite and keeps that process running for subsequent rewrites. It creates a fresh session before and after each request and verifies that the session has no messages, queued prompts, or active generation. Successful rewrites keep the process warm; cancellation, errors, or quitting Rewrite stop it. A model/provider change or a request more than three minutes after process startup creates a new process with refreshed credentials. An unexpected exit is reported without automatically resubmitting the text; the next rewrite starts Pi again.

Rewrite reads the selection only when invoked and sends no rewrite request until a style is chosen. It stores only provider, model, and shortcut preferences; it does not log text, results, or raw processor errors.

Replacement uses the captured Accessibility element directly, without changing the clipboard or simulating paste. Automatic replacement also requires the original app to remain in the foreground. It requires the original field, window, full field value, and UTF-16 selection to still match. Observed text/selection changes permanently invalidate the request. **Capture and replacement never change the clipboard or send a global paste keystroke.** The destination app controls Undo and formatting behavior.

Some apps expose readable text but cannot safely replace it. Rewrite leaves the text untouched and explains the limitation in the menu bar. Changed selections or app switches cancel delivery instead of editing a stale or background field. Apps that do not expose selected text (including secure fields, some browser content, terminals, and custom editors) cannot be rewritten. There is no clipboard or paste-keystroke fallback. Selections are limited to 24,000 UTF-16 units; rich styling is not transmitted, but textual structure is preserved. AI edits can still be imperfect: check the text after replacement and use Undo if needed.

Local development:

```sh
./build.sh                 # build/Rewrite.app, ad-hoc signed
./install.sh --local       # build and install this checkout
./tests/run.sh             # offline focused tests
./tests/run.sh --pi-check  # installed Pi discovery, no inference
./tests/run.sh --live openai
./tests/run.sh --live anthropic
./tests/feedback.sh        # Option-R, six style shortcuts, and menu-bar status/error checks
./tests/selection.sh --app com.apple.TextEdit --replace
./tests/selection.sh --app com.apple.TextEdit --automatic # live Pi rewrite + automatic replacement
./tests/selection.sh --app com.apple.TextEdit --background # reject background replacement
```

Live tests send a fixed, disposable grammar example using existing authentication. Selection tests require selecting exactly `She go to the library yesterday.` in a disposable document; they refuse other text. `Rewrite.app/Contents/MacOS/Rewrite --review` adds a Dock presence for inspection and uses the production selection and processing paths. See [runtime verification](docs/verification.md) for tested apps and concrete limitations. Locally signed rebuilds may require re-enabling Accessibility permission.

Interfaces verified against installed Pi help and source: [Pi CLI](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/README.md), [JSON event stream](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/json.md).
