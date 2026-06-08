# pi-chat

Pi extension bridging Discord and Telegram to a sandboxed pi session via Gondolin micro-VMs.

## Architecture

```
Discord/Telegram ←→ Live Adapter ←→ Runtime (log, jobs, slices) ←→ pi agent
                                        ↕
                                   Gondolin VM (Alpine + bash)
                                   /workspace  /shared
```

- **One VM per connection.** Started on `/chat-connect`, closed on `/chat-disconnect`. `/chat-spawn-all` launches one detached tmux/pi worker per configured channel using the `--chat-conversation <account/channel>` extension flag. `/chat-workers`, `/chat-open-all`, and `/chat-kill-all` manage those workers through tmux. Workers write status JSON to `~/.pi/agent/chat/worker-status/`; the `chat_workers` tool reads it.
- **One JSONL log per channel.** Append-only event stream: inbound, outbound, job lifecycle.
- **Trigger-based dispatch.** Mentions in channels, every message in DMs. Triggers queue jobs; jobs produce slices of inbound records for the agent.
- **Tools run inside the VM.** `read`, `write`, `edit`, `bash` are routed through Gondolin. `chat_history` and `chat_attach` run on the host.

## Entry point

`index.ts` — Extension factory. Registers tools, commands, event handlers, connection lifecycle, and tmux spawning.

## Key files

### Core types
- `src/core/config-types.ts` — Config, account, channel, secret, and resolved conversation types.
- `src/core/runtime-types.ts` — Log record types, job types, dispatch types.
- `src/core/discovery-types.ts` — Discovery snapshot types (channels, users, roles).
- `src/core/keys.ts` — Channel key derivation.

### Config & storage
- `src/config.ts` — Load/save config, resolve conversations, storage paths. Everything under `~/.pi/agent/chat/`.
- `src/discovery-store.ts` — Read/write discovery snapshots (cached channel/user/role lists).
- `src/log.ts` — JSONL log read/write, locking, attachment materialization, directory setup.

### Runtime
- `src/runtime.ts` — `ConversationRuntime`: log state machine, job queue, slice construction, prompt building, checkpoint management. Owns trigger logic, access policy, control command parsing.

### Gondolin sandbox
- `src/gondolin.ts` — `ConversationSandbox`: VM lifecycle, secret environment setup, tool operation factories (read/write/edit/ls/find/grep/bash), guest/host path translation.

### Secrets
- `src/secrets.ts` — Encrypted secret exchange: RSA keypair generation, widget URL construction, hybrid RSA-OAEP + AES-256-GCM decryption.

### Live adapters
- `src/live/types.ts` — `LiveConnection` and `LiveConnectionHandlers` interfaces.
- `src/live/index.ts` — Adapter router (Discord vs Telegram).
- `src/live/discord.ts` — Discord adapter: discord.js gateway, catch-up pagination, REST message sending with chunking and formatting, reply-to, auto-reconnect on disconnect.
- `src/live/telegram.ts` — Telegram adapter: long-polling, media group debounce, initial catch-up, chunked sending with Markdown formatting.
- `src/live/common.ts` — Shared: attachment download/storage, MIME detection, bot mention detection.

### Rendering
- `src/render/format.ts` — Service-specific markdown normalization and message length limits.
- `src/render/chunking.ts` — Text chunking for service message limits.
- `src/render/streaming.ts` — `StreamingPreview`: chunked preview transport (currently unused, kept for potential future streaming).
- `src/render/streaming-markdown.ts` — Streaming markdown renderer (currently unused).

### Services (setup/discovery)
- `src/services/index.ts` — Account snapshot refresh, identity update.
- `src/services/discord.ts` — Discord bot validation, server listing, channel/role/user discovery.
- `src/services/telegram.ts` — Telegram bot validation, identity fetch.
- `src/services/types.ts` — Shared service types.

### TUI
- `src/tui/chat-config.ts` — `/chat-config` UI: account/channel management, access policy, secrets config.
- `src/tui/dialogs.ts` — Shared dialog helpers: select, notice, loader, toggle.
- `src/tui/discord-setup.ts` — Guided Discord account setup (token, server selection, invite flow).
- `src/tui/telegram-setup.ts` — Guided Telegram account setup (token, DM/group observation).

## Storage layout

```
~/.pi/agent/chat/
├── config.json
├── cache/
└── accounts/<account>/
    ├── shared/                    → /shared in VM
    │   ├── memory.md
    │   └── skills/
    └── channels/<channel>/
        ├── channel.jsonl
        ├── .lock
        ├── workspace/             → /workspace in VM
        │   ├── memory.md
        │   ├── skills/
        │   ├── incoming/
        │   ├── .secrets/
        │   └── SYSTEM.md
        └── gondolin/
            └── session.json
```

## Log record types

`checkpoint`, `inbound`, `job_queued`, `outbound`, `job_completed`, `job_failed`, `error`.

## Job/slice semantics

- `job_queued` records a trigger. `sliceStartRecordId` is derived at dispatch time from the last `job_completed.triggerRecordId`.
- Failed jobs do not advance the consumption boundary.
- The prompt slice includes all inbound records between the last completed boundary and the trigger.
- On reconnect, catch-up messages are logged but do not trigger until a new trigger arrives after arming.

## Remote control commands

Parsed by `ConversationRuntime.parseControlCommand()`: `stop`, `new`, `compact`, `status`. Handled before normal ingest in the `onMessage` path.

## Secret exchange flow

1. Agent calls `chat_request_secret` tool → RSA keypair generated, widget URL sent to chat.
2. User opens `pi.dev/secret#<base64>`, pastes secret, gets encrypted blob.
3. User pastes `!secret:<id>:<payload>` back into chat.
4. pi-chat intercepts (before trigger check), decrypts, writes to `/workspace/.secrets/<name>`, notifies agent.

## Conventions

- `npm run check` = biome + tsc.
- No ambient host env leaks into VM.
- All paths shown to the model use guest-relative paths (`/workspace/...`, `/shared/...`).
- Transcript lines include `[uid:ID]` for tamper-resistant user identification.
