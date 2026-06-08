# pi-chat

A pi extension that bridges Telegram chats to a sandboxed pi session. Each connected channel gets its own [Gondolin](https://github.com/earendil-works/gondolin) micro-VM with persistent workspace, shared storage, memory, and skills.

## Quick Start

```bash
# Install
pi install /path/to/pi-chat
# or
pi -e /path/to/pi-chat

# Configure accounts and channels
/chat-config

# Connect
/chat-connect
```

### Requirements

- [QEMU](https://www.qemu.org/) installed (`brew install qemu` on macOS)
- Gondolin guest image (downloaded automatically on first connect)
- A Telegram bot token
- `tmux` for multi-channel worker orchestration

---

## Features

- **Telegram DMs/groups**
- **Gondolin VM sandbox** per connection — tools run inside an isolated Alpine Linux micro-VM
- **Persistent workspace** and **shared storage** across sessions
- **Streamed preview** responses with edit-in-place
- **Reply-to-trigger** — bot replies are attached to the triggering message
- **Durable memory** — account-wide and channel-specific memory files
- **Skills** — agent-created reusable tools, auto-discovered and injected into the prompt
- **Encrypted secret exchange** — securely pass credentials via browser-based encryption
- **Remote control** — stop, compact, new session, and status via chat commands
- **Chat history** tool for searching older messages
- **File attachments** — send and receive files between chat and the VM

---

## Setup

### Telegram

1. Create a bot via [@BotFather](https://t.me/BotFather)
2. Run `/chat-config` → Create account
3. Enter your bot token
4. Add DMs or groups through the guided setup

---

## Commands

| Command | Description |
|---------|-------------|
| `/chat-config` | Configure accounts, channels, and secrets |
| `/chat-connect` | Connect to a configured channel |
| `/chat-disconnect` | Disconnect the current channel |
| `/chat-status` | Show connection status, model, usage, context |
| `/chat-list` | List configured channels |
| `/chat-spawn-all` | Spawn every configured channel in detached tmux/pi sessions |
| `/chat-spawn-all --restart` | Restart those tmux/pi sessions |
| `/chat-workers` | Show managed tmux/pi worker status |
| `/chat-open-all` | Open running workers in a tiled tmux dashboard |
| `/chat-kill-all` | Kill all managed tmux/pi workers |
| `/chat-new` | Start a new pi session, keeping the chat connection |

Workers also write status snapshots every 15 seconds under `~/.pi/agent/chat/worker-status/`. The `chat_workers` tool exposes the same status to an orchestrating pi agent.

---

## Remote Control

Users in the connected chat can send these commands (with or without mentioning the bot):

| Command | Effect |
|---------|--------|
| `stop` | Abort the current turn |
| `status` | Show model, usage, context stats |
| `compact` | Trigger context compaction |
| `new` | Start a new pi session |

---

## Storage Layout

Everything lives under `~/.pi/agent/chat/`:

```
~/.pi/agent/chat/
├── config.json                          # Accounts, channels, secrets
├── cache/                               # Discovery cache
└── accounts/<account>/
    ├── shared/                          # Mounted as /shared in VM
    │   ├── memory.md                    # Account-wide persistent memory
    │   └── skills/                      # Account-wide skills
    └── channels/<channel>/
        ├── channel.jsonl                # Chat log
        ├── .lock                        # Runtime lock
        ├── workspace/                   # Mounted as /workspace in VM
        │   ├── memory.md                # Channel-specific persistent memory
        │   ├── skills/                  # Channel-specific skills
        │   ├── incoming/                # Downloaded attachments
        │   ├── .secrets/                # Encrypted secrets
        │   └── SYSTEM.md                # Environment modification log
        └── gondolin/                    # VM state
            └── session.json
```

---

## VM Environment

Each connection starts a Gondolin micro-VM with:

- **Alpine Linux** with bash pre-installed
- `/workspace` → channel workspace directory
- `/shared` → account shared directory
- Tools: `read`, `write`, `edit`, `bash`
- All outbound HTTP/TLS open by default

The agent sees `/workspace` as its working directory.

---

## Memory

Two persistent memory files, injected into the system prompt on every turn:

| File | VM Path | Scope |
|------|---------|-------|
| Account memory | `/shared/memory.md` | Shared across all channels for this account |
| Channel memory | `/workspace/memory.md` | Specific to this channel |

The agent is instructed to write durable facts and preferences to these files when asked to remember something. Account-wide goes to `/shared/memory.md`, channel-specific to `/workspace/memory.md`.

---

## Skills

The agent can create reusable tools as skills, following the [Agent Skills standard](https://agentskills.io):

- **Account-wide:** `/shared/skills/`
- **Channel-specific:** `/workspace/skills/`

A skill is either a single `.md` file (e.g. `skills/foo.md`) or a directory with `SKILL.md` plus supporting files (e.g. `skills/foo/SKILL.md`, `skills/foo/run.sh`).

Each skill needs YAML frontmatter:

```yaml
---
name: skill-name
description: Short description of what this skill does
---
```

Skills are automatically discovered and listed in the system prompt. The agent reads the full skill file before using it.

---

## Secrets

### Config Secrets (Gondolin HTTP hooks)

Configure secrets at three levels via `/chat-config`:

- **Global** — shared across all accounts
- **Per account** — shared across channels of that account
- **Per channel** — specific to one channel

Each secret has a value and allowed host patterns. Gondolin replaces placeholder env vars with real values only for outbound HTTP requests to allowed hosts. The agent never sees the real secret value.

### Runtime Secrets (encrypted exchange)

For credentials the agent needs at runtime (API keys for skills, OAuth files, etc.):

1. Agent calls the `chat_request_secret` tool
2. A link to `pi.dev/secret` is sent to the chat with an embedded public key
3. User clicks, pastes the secret, and gets an encrypted blob
4. User pastes the blob back into chat
5. pi-chat decrypts it (RSA-OAEP + AES-256-GCM) and stores it at `/workspace/.secrets/<name>`
6. Agent is notified and can use the file

The encrypted blob is useless without the ephemeral private key held in pi-chat's memory.

---

## Tools

| Tool | Description |
|------|-------------|
| `read` | Read files (routed through Gondolin VM) |
| `write` | Create/overwrite files |
| `edit` | Precise in-place edits |
| `bash` | Execute commands (runs `/bin/bash` in the VM) |
| `chat_history` | Search older messages from the chat log |
| `chat_attach` | Queue files to send with the next reply |
| `chat_request_secret` | Request a secret from the user via encrypted exchange |

---

## Credits

pi-chat includes vendored/adapted logic inspired by [Vercel Chat SDK](https://github.com/vercel/ai) (MIT):

- `src/render/format.ts`
- `src/render/streaming-markdown.ts`
- `src/render/streaming.ts`

---

## License

MIT
