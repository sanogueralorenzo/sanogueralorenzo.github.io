# A1R

![A1R banner](assets/a1r-banner.png)

> A quiet, fast personal assistant that can code.

A1R is one small local runtime for personal and coding work. Its CLI, Telegram bot, and native macOS app all use the same execution loop, sessions, memory, tools, and context.

```text
input → decide → load context → act → remember
```

A1R owns that entire path. It uses OpenAI models through the Responses API, but does not use the OpenAI Agents SDK, Pi SDK, Hermes, Laya, LangChain, or another agent framework. Pi inspired the direct terminal experience, Hermes inspired durable memory and gateways, and Laya inspired the small typed router.

## Try it

Requirements: macOS or Linux, Node 22.13 or newer, and an OpenAI API key.

```bash
cd tools/a1r
npm install
npm run build
npm link
a1r setup
a1r chat --dev
```

`a1r setup` validates the key and stores it in macOS Keychain (or a mode-0600 local credential file on other systems). The CLI picks the session, work type, model, memory, and tools. There is no model or worker setup.

Useful commands inside the CLI:

- `/new` starts a fresh conversation.
- `/status` shows the current saved conversation.
- `/help` gives the short usage reminder.
- `Ctrl-C` stops an active response without discarding the session.
- `/quit` exits.

Development mode watches runtime code and restarts it within seconds. The terminal stays open, reconnects to the replacement runtime, and resumes the same SQLite-backed session. Transcripts, memory, runs, and project state are persisted before the client sees completion.

## Telegram

```bash
a1r telegram setup
```

The setup flow validates a dedicated BotFather token, refuses bots already attached to a webhook, stores the token privately, and prints a single-use pairing link that expires after ten minutes. It then starts a local long-polling gateway. Only the paired private Telegram account can use it.

The gateway is deliberately thin: messages enter the local runtime over the same authenticated HTTP/SSE protocol as the CLI, and replies are streamed into one updating Telegram message. `/stop` cancels the current run. Coding requests automatically resume the most recent local coding project; ordinary requests use the personal conversation.

The computer and A1R gateway must be online for Telegram access.

## Native macOS app

```bash
npm run macos:run
```

This builds and opens a native SwiftUI client—no web view and no duplicated agent logic. It discovers or starts the shared local runtime, guides first-time OpenAI connection, streams the conversation, shows quiet tool activity, and supports cancellation and new conversations.

For a separately installed runtime, set `A1R_EXECUTABLE` to the `a1r` executable before launching the app. A signed `.app` bundle and login item are distribution work; the source-built native client is usable now.

## How it works

- `src/core/runtime.ts` owns the Responses API tool loop.
- `src/core/router.ts` makes a fast local typed decision: personal or coding, then fast, standard, or deep.
- `src/core/store.ts` owns SQLite sessions, transcripts, memories, gateway bindings, and interruption records.
- `src/core/tools.ts` owns scoped file, search, shell, memory, and internal delegation tools.
- `src/server` exposes a loopback-only bearer-authenticated HTTP/SSE protocol.
- `src/cli`, `src/telegram`, and `macos` are clients of that protocol.

The default model policy is centralized and automatic:

- fast: `gpt-5.6-luna`
- standard: `gpt-5.6-terra`
- deep: `gpt-6-astra`

Environment overrides exist for deployment compatibility, but normal use never asks the user to pick a model.

Memory is local and intentionally small. A1R injects only relevant durable facts, retains the bounded recent transcript, and lets the model save an explicit non-secret fact with the `remember` tool. Coding file tools are confined to the active project. Commands use an explicit development-program allowlist and argument array instead of a shell, drop secret-bearing environment variables, and reject traversal and destructive forms. On macOS they also run in a project-scoped, network-denied system sandbox. Suspected secrets are redacted before transcript persistence and refused by memory.

Deep tasks may call `delegate_task` zero, one, or several times. Workers use the same OpenAI-only model boundary, receive bounded read-only context, and return findings to the parent; clients see one coherent response.

## Verify

```bash
npm run check
swift build --package-path macos
swift run --package-path macos A1RProtocolCheck
```

The normal test suite is offline and uses a fake model to exercise streaming, function calls, memory, session persistence, gateway helpers, and the full owned execution loop. A live smoke test only requires running `a1r setup` first.

## Data

A1R keeps its local state under `~/.a1r` by default:

- `a1r.sqlite` — sessions, transcript, memories, runs, and gateway links
- `runtime.json` — mode-0600 local discovery token and port
- `telegram.json` — bot identity and paired Telegram user (never the bot token)
- `credentials.json` — non-macOS fallback only; mode 0600

Set `A1R_HOME` to isolate a development or test instance.

The state directory is forced to mode 0700 and data files to 0600. In-progress text is checkpointed during generation; after an unclean restart A1R marks the run interrupted and restores its partial output to the transcript.

Website: [a1r.dev](https://a1r.dev)
