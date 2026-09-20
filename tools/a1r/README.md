# A1R

![A1R banner](assets/a1r-banner.png)

> A quiet, fast personal assistant that can code.

A1R is one small local runtime for personal and coding work. Its CLI, Telegram bot, and native macOS app share A1R-owned sessions, memory, routing, recovery, project selection, and a single client protocol.

```text
input → decide → load A1R context → selected backend → remember
```

A1R supports two OpenAI backends:

- **Continue with ChatGPT (recommended):** A1R launches the official [`codex app-server`](https://developers.openai.com/codex/app-server) subprocess and delegates each agent turn to Codex, which owns ChatGPT authentication, subscription accounting, and turn execution. Eligible ChatGPT/Codex plans use their included allowance.
- **API-key billing:** A1R uses its independent Responses API execution and tool loop. This is the original runtime and remains fully intact.

The ownership boundary is deliberate. Even in Codex mode, A1R—not app-server—owns the CLI, Telegram and macOS clients, local gateway, session catalog, long-term memory, project routing, recovery, and hot reload. A1R never reads `~/.codex/auth.json`, never handles Codex access tokens, and never calls private ChatGPT or Codex endpoints.

## Try it

Requirements: macOS or Linux, Node 22.13 or newer, and either the official Codex CLI with an eligible ChatGPT account or an OpenAI API key.

```bash
cd tools/a1r
npm install
npm run build
npm link
a1r setup
a1r chat --dev
```

`a1r setup` recommends **Continue with ChatGPT**, detects Codex and the active account, opens the documented browser login when required, shows the plan and available usage returned by app-server, and remembers the backend. Device-code login and direct API-key setup are also available:

```bash
a1r setup --device-code
a1r setup --api-key
```

If Codex is unavailable or its included allowance is exhausted, setup falls back cleanly to the API-key flow. API keys are validated and stored in macOS Keychain, or in a mode-0600 credential file on other systems. Subscription credentials remain entirely under Codex app-server ownership. A1R never silently changes billing modes during a turn.

Useful commands inside the CLI:

- `/new` starts a fresh A1R conversation.
- `/status` shows the current session and selected billing mode.
- `/help` gives the short usage reminder.
- `Ctrl-C` interrupts the active backend turn without discarding the A1R session.
- `/quit` exits.

Development mode watches A1R code, prompts, tools, and configuration. The terminal reconnects to a replacement runtime within seconds, while SQLite-backed sessions, transcripts, memory, project state, and opaque Codex thread bindings survive. The app-server subprocess is supervised and a disconnected turn is retried only before any response or tool activity, avoiding duplicated actions.

## Telegram

```bash
a1r telegram setup
```

The guided flow first selects the shared OpenAI backend, then validates a dedicated BotFather token, refuses bots already attached to a webhook, stores the token privately, and prints a single-use pairing link that expires after ten minutes. Only the paired private Telegram account can use it.

Telegram remains thin: messages enter the same local runtime over authenticated HTTP/SSE. `/stop` cancels the active Responses or Codex turn. Coding requests resume the most recent local coding project; ordinary requests use the personal conversation. The computer and gateway must remain online.

## Native macOS app

```bash
npm run macos:run
```

The native SwiftUI client has no web view and no agent implementation. Its onboarding recommends ChatGPT, launches browser or device-code login through the runtime, displays plan and allowance information, and offers API-key billing as the fallback. It then streams the same normalized A1R events as the CLI and Telegram clients.

For a separately installed runtime, set `A1R_EXECUTABLE` to the `a1r` executable before launching the app. A signed `.app` bundle and login item remain distribution work; the source-built native client is usable now.

## Architecture

- `src/core/runtime.ts` owns session selection, routing, memory flow, transcript checkpoints, recovery, and backend-neutral events.
- `src/core/backend.ts` is the small backend boundary.
- `src/core/responses-backend.ts` owns A1R's independent Responses API tool loop.
- `src/codex/app-server.ts` supervises documented JSONL JSON-RPC over stdio.
- `src/codex/backend.ts` maps A1R sessions to opaque Codex thread IDs and normalizes app-server events.
- `src/core/store.ts` owns SQLite sessions, transcripts, memories, backend bindings, gateway bindings, and interruption records.
- `src/server` exposes the loopback-only bearer-authenticated HTTP/SSE protocol used by every client.

In API-key mode, the local router automatically chooses personal or coding work and fast, standard, or deep execution. In Codex mode, A1R still makes the personal/coding and project/session decision, injects relevant A1R memory and instructions, and lets Codex choose and execute the agent turn. Users never choose a model or manage workers.

Memory is local and intentionally small. Relevant facts are injected into either backend. Explicit “remember that …” requests are captured by the A1R runtime so long-term memory remains available across backend changes.

## Verify

```bash
npm run check
swift build --package-path macos
swift run --package-path macos A1RProtocolCheck
```

Offline tests use a real fake app-server subprocess and cover browser/device login, streaming, cancellation, reconnection, expired authentication, exhausted allowance, and API fallback. To run the optional live smoke test against the active Codex account without reading or printing any stored credential:

```bash
A1R_LIVE_CODEX=1 npm test -- src/codex/codex.live.test.ts
```

The smoke test is opt-in because it consumes a small amount of included Codex usage.

## Data

A1R keeps its state under `~/.a1r` by default:

- `a1r.sqlite` — A1R sessions, transcripts, memories, runs, selected backend, and opaque backend/gateway bindings
- `runtime.json` — mode-0600 local discovery token and port
- `telegram.json` — bot identity and paired Telegram user, never the bot token
- `credentials.json` — non-macOS fallback for A1R's API key and Telegram token only; mode 0600

Codex authentication is not copied into A1R storage. Set `A1R_HOME` to isolate a development or test instance.

Website: [a1r.dev](https://a1r.dev)
