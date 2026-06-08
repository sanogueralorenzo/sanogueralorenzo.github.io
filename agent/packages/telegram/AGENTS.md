# Agent Telegram

Telegram bridge for local agent sessions with direct host access.

## Architecture

```text
Telegram ←→ Live Adapter ←→ Runtime (log, jobs, slices) ←→ pi agent ←→ host tools
```

- **Host access.** Remote Telegram turns run with the same local filesystem and process access as the pi session where this extension is installed.
- **One JSONL log per channel.** Append-only event stream: inbound, outbound, job lifecycle.
- **Trigger-based dispatch.** Mentions in groups, every message in DMs. Triggers queue jobs; jobs produce slices of inbound records for the agent.
- **Host tools.** `read`, `write`, `edit`, and `bash` run directly on the host cwd and can use absolute host paths. `chat_history`, `chat_attach`, and `chat_request_secret` are available during chat turns.
- **Workers.** `agent telegram start` launches the Telegram worker as a user service. Workers write status JSON to `~/.pi/agent/chat/worker-status/`.

## Entry point

`index.ts` — Runtime adapter loaded by the foreground/service worker. Registers tools, event handlers, and Telegram connection lifecycle.

## Key files

### Core types
- `src/core/config-types.ts` — Config, account, channel, and resolved conversation types.
- `src/core/runtime-types.ts` — Log record types, job types, dispatch types.
- `src/core/discovery-types.ts` — Discovery snapshot types (channels, users, roles).
- `src/core/keys.ts` — Channel key derivation.

### Config & storage
- `src/config.ts` — Load/save config, resolve conversations, storage paths. Everything under `~/.pi/agent/chat/`.
- `src/discovery-store.ts` — Read/write discovery snapshots.
- `src/log.ts` — JSONL log read/write, locking, attachment materialization, directory setup.

### Runtime
- `src/runtime.ts` — `ConversationRuntime`: log state machine, job queue, slice construction, prompt building, checkpoint management. Owns trigger logic, access policy, control command parsing.

### Secrets
- `src/secrets.ts` — Encrypted secret exchange: RSA keypair generation, widget URL construction, hybrid RSA-OAEP + AES-256-GCM decryption.

### Live adapters
- `src/live/types.ts` — `LiveConnection` and `LiveConnectionHandlers` interfaces.
- `src/live/index.ts` — Telegram live adapter entrypoint.
- `src/live/telegram.ts` — Telegram adapter: long-polling, media group debounce, initial catch-up, chunked sending with Markdown formatting.
- `src/live/common.ts` — Shared: attachment download/storage, MIME detection, bot mention detection.

### Rendering
- `src/render/format.ts` — Telegram markdown normalization and message length limit.
- `src/render/chunking.ts` — Text chunking for Telegram message limits.
- `src/render/streaming.ts` — `StreamingPreview`: chunked preview transport.
- `src/render/streaming-markdown.ts` — Streaming markdown renderer.

### Services/setup
- `src/services/index.ts` — Account snapshot refresh, identity update.
- `src/services/telegram.ts` — Telegram bot validation, identity fetch.
- `src/services/types.ts` — Shared service types.

### CLI/setup
- `src/cli.ts` — `agent telegram ...` commands for login, run, start/stop, restart, enable/disable, status, and doctor.
- `src/tui/dialogs.ts` — Remaining pi UI helpers used by the runtime extension for notices/loaders/selectors.

## Storage layout

```text
~/.pi/agent/chat/
├── config.json
├── cache/
├── memory.md
├── SYSTEM.md
├── skills/
├── secrets/
└── accounts/<account>/
    └── channels/<channel>/
        ├── channel.jsonl
        ├── .lock
        └── channel/
            └── incoming/
```

## Log record types

`checkpoint`, `inbound`, `job_queued`, `outbound`, `job_completed`, `job_failed`, `error`.

## Job/slice semantics

- `job_queued` records a trigger. `sliceStartRecordId` is derived at dispatch time from the last `job_completed.triggerRecordId`.
- Failed jobs do not advance the consumption boundary.
- The prompt slice includes all inbound records between the last completed boundary and the trigger.
- On reconnect, catch-up messages are logged but do not trigger until a new trigger arrives after arming.

## Remote control commands

Parsed by `ConversationRuntime.parseControlCommand()`: `stop`, `compact`, `status`. Handled before normal ingest in the `onMessage` path.

## Secret exchange flow

1. Agent calls `chat_request_secret` tool → RSA keypair generated, widget URL sent to chat.
2. User opens `pi.dev/secret#<base64>`, pastes secret, gets encrypted blob.
3. User pastes `!secret:<id>:<payload>` back into chat.
4. agent-telegram intercepts, decrypts, writes to `~/.pi/agent/chat/secrets/<name>`, and notifies the agent.

## Conventions

- `npm run check` = biome + tsc.
- Remote chat access is trusted host access. Do not connect untrusted chats.
- Paths shown to the model are real host paths.
- Transcript lines include `[uid:ID]` for tamper-resistant user identification.
