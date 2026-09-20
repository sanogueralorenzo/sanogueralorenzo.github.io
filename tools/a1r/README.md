# A1R

![A1R banner](assets/a1r-banner.png)

> A quiet, fast personal assistant that can code.

A1R is one small local runtime for personal and coding work. Its CLI, Telegram bot, and native macOS app share A1R-owned sessions, memory, routing, recovery, project selection, and a single client protocol.

```text
input → decide → load A1R context → selected backend → remember
```

A1R supports two OpenAI backends:

- **Continue with ChatGPT (recommended):** A1R launches the official [`codex app-server`](https://developers.openai.com/codex/app-server) subprocess inside an A1R-specific Codex profile and delegates each agent turn to Codex, which owns ChatGPT authentication, subscription accounting, and turn execution. Eligible ChatGPT/Codex plans use their included allowance.
- **API-key billing:** A1R uses its independent Responses API execution and tool loop. This is the original runtime and remains fully intact.

The ownership boundary is deliberate. Even in Codex mode, A1R—not app-server—owns the CLI, Telegram and macOS clients, local gateway, session catalog, long-term memory, project routing, recovery, and hot reload. A1R gives app-server a locked-down profile at `~/.a1r/codex`, but never reads its credential files, never handles Codex access tokens, never touches the global `~/.codex` login, and never calls private ChatGPT or Codex endpoints. The app-server child also drops ambient OpenAI/Codex credential variables so they cannot silently bypass the private profile. API-key mode is a separate backend that A1R selects only when the user explicitly chooses it.

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

`a1r setup` asks for exactly one setup method:

```text
Connect A1R

1. Set up with ChatGPT browser
2. Set up headless or remote device (one-time code)
3. Set up with OpenAI API key (independent usage-based billing)
Select 1–3 (Enter for 1):
```

Browser setup opens the authorization page without printing its long URL unless opening the browser fails. Headless setup prints the URL and one-time code it needs. Every successful setup ends with `Connect Success`.

The corresponding non-interactive commands are:

```bash
a1r setup --chatgpt
a1r setup --headless
a1r setup --api-key
```

Browser and headless login both authenticate the same ChatGPT subscription and persist only inside `~/.a1r/codex`. [Headless login](https://developers.openai.com/docs/auth) may need to be enabled in ChatGPT security settings or by a workspace administrator. A failed, cancelled, expired, or timed-out login stops with a clear error and preserves the previously selected backend and all A1R state; A1R never switches login flows or billing modes automatically. Neither flow signs out, replaces, copies, or reuses the global Codex CLI account.

Upgrading from A1R 0.2.0 intentionally does not copy the previously shared Codex CLI credentials. Existing A1R sessions, transcripts, memories, projects, and opaque thread bindings remain in place, but subscription mode asks for one new A1R-specific ChatGPT login. If an old thread binding is unavailable in the private profile, A1R starts a replacement thread with the saved A1R transcript and updates the binding. Run `a1r setup` once to complete the safe migration.

If Codex is unavailable or its included allowance is exhausted, ChatGPT setup stops and explains the next step. It never automatically switches to API-key billing. Users who independently choose `a1r setup --api-key` have their key validated and stored in macOS Keychain, or in a mode-0600 credential file on other systems. Subscription credentials remain entirely under Codex app-server ownership. A1R never silently changes billing modes during setup or a turn.

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
a1r telegram setup --headless # remote/headless host
```

The guided flow first uses the same three browser, headless-device, or API-key choices as the CLI, then validates a dedicated BotFather token, refuses bots already attached to a webhook, stores the token privately, and prints a single-use pairing link that expires after ten minutes. Only the paired private Telegram account can use it.

Telegram remains thin: messages enter the same local runtime over authenticated HTTP/SSE. `/stop` cancels the active Responses or Codex turn. Coding requests resume the most recent local coding project; ordinary requests use the personal conversation. The computer and gateway must remain online.

## Native macOS app

```bash
npm run macos:run
```

The native SwiftUI client has no web view and no agent implementation. Its onboarding recommends ChatGPT, explains the private A1R profile, launches browser login through the shared runtime, and finishes on the neutral local confirmation page. It points remote users to `a1r setup --headless`, displays plan and allowance information, and keeps API-key billing as a separate explicit choice. It then streams the same normalized A1R events as the CLI and Telegram clients.

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

Offline tests use a real fake app-server subprocess and cover neutral browser login, explicit headless device login, incorrect-flow rejection, cancellation, expiration, timeout, state preservation, no automatic billing fallback, streaming, reconnection, and exhausted allowance. To run the optional live smoke test against the active A1R Codex profile without reading or printing any stored credential:

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
- `codex/` — mode-0700 private `CODEX_HOME` used only by A1R's app-server process; app-server exclusively owns any credentials inside it

Codex authentication is not copied from the global CLI or exposed to the A1R runtime. Set `A1R_HOME` to isolate a development or test instance, including its Codex profile.

Website: [a1r.dev](https://a1r.dev)
