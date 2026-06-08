# pi-chat Telegram

A pi extension that bridges Telegram DMs/groups to a local pi session.

This package intentionally runs with **host access by default**: remote Telegram turns use the same local filesystem and process access as the pi session where the extension is installed.

## Quick Start

```bash
# Install
pi install /path/to/telegram
# or
pi -e /path/to/telegram

# Configure Telegram accounts and channels
/chat-config

# Connect
/chat-connect
```

### Requirements

- A Telegram bot token
- `tmux` for multi-channel worker orchestration
- Optional for voice transcription: Python with `faster-whisper` available to the worker

## Features

- Telegram DMs/groups
- Direct host-machine access for coding tools
- Persistent account/channel storage across sessions
- Streamed preview responses with edit-in-place
- Reply-to-trigger responses
- Durable account-wide and channel-specific memory files
- Skills auto-discovered and injected into the prompt
- Encrypted runtime secret exchange
- Remote control: stop, compact, new session, status
- Chat history search
- File attachments in both directions
- Telegram voice/audio transcription through a local Whisper worker

## Setup

1. Create a bot via [@BotFather](https://t.me/BotFather)
2. Run `/chat-config` → Create account
3. Enter your bot token
4. Add DMs or groups through the guided setup

## Commands

| Command | Description |
|---------|-------------|
| `/chat-config` | Configure Telegram accounts and channels |
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

## Remote Control

Users in the connected chat can send these commands:

| Command | Effect |
|---------|--------|
| `stop` | Abort the current turn |
| `status` | Show model, usage, context stats |
| `compact` | Trigger context compaction |
| `new` | Start a new pi session |

## Storage Layout

Everything lives under `~/.pi/agent/chat/`:

```text
~/.pi/agent/chat/
├── config.json
├── cache/
├── secrets/                              # Runtime secrets from chat_request_secret
└── accounts/<account>/
    ├── account/
    │   ├── memory.md
    │   └── skills/
    └── channels/<channel>/
        ├── channel.jsonl
        ├── .lock
        └── channel/
            ├── memory.md
            ├── skills/
            ├── incoming/
            └── SYSTEM.md
```

The agent's actual working directory is the local pi session cwd. The account/channel storage paths above are regular host paths and can be read/written directly.

## Voice Messages

Telegram `voice` and `audio` messages are downloaded as audio attachments and transcribed before the message is added to the chat transcript.

Environment knobs:

```text
PI_CHAT_STT_ENABLED   default: 1; set 0/false/no to disable
PI_CHAT_STT_PYTHON    Python executable for the worker
PI_CHAT_STT_MODEL     default: base
PI_CHAT_STT_LANGUAGE  default: en
PI_CHAT_STT_DEVICE    default: cpu
PI_CHAT_STT_COMPUTE_TYPE default: int8
```

The worker expects `faster-whisper` to be importable from the selected Python environment.

## Tools

| Tool | Description |
|------|-------------|
| `read` | Read local host files |
| `write` | Create/overwrite local host files |
| `edit` | Precise in-place edits on local host files |
| `bash` | Execute host shell commands |
| `chat_history` | Search older messages from the chat log |
| `chat_attach` | Queue local files to send with the next reply |
| `chat_request_secret` | Request a secret from the user via encrypted exchange; stores files under `~/.pi/agent/chat/secrets/` |

## Security Model

This package is for trusted Telegram chats only.

A connected chat can drive an agent with local host access. Configure Telegram channels and allowed users carefully. Do not connect untrusted groups or users.

## License

MIT
