# Agent Telegram

A Telegram bridge for a local agent session.

This package intentionally runs with **host access by default**: remote Telegram turns use the same local filesystem and process access as the local agent process.

## Quick Start

```bash
# Configure Telegram account and trusted chat
agent telegram login

# Start the bridge
agent telegram start

# Optional: keep it running after reboot/login
agent telegram enable
```

### Requirements

- A Telegram bot token
- Optional for voice transcription: Python with `faster-whisper` available to the worker

## Features

- Telegram DMs/groups
- Direct host-machine access for coding tools
- Persistent account/channel storage across sessions
- Streamed preview responses with edit-in-place
- Reply-to-trigger responses
- One simple durable memory file
- Skills auto-discovered and injected into the prompt
- Encrypted runtime secret exchange
- Remote control: stop, compact, status
- Chat history search
- File attachments in both directions
- Telegram voice/audio transcription through a local Whisper worker

## Setup

1. Create a bot via [@BotFather](https://t.me/BotFather)
2. Run `agent telegram login`
3. Enter your bot token
4. Send a message to the bot when prompted

## Commands

| Command | Description |
|---------|-------------|
| `agent telegram login` | Configure Telegram bot and trusted chat |
| `agent telegram run [chat]` | Run the Telegram worker in the foreground |
| `agent telegram start [chat]` | Start the Telegram worker as a user service |
| `agent telegram stop` | Stop the Telegram worker service |
| `agent telegram restart [chat]` | Restart the Telegram worker service |
| `agent telegram status` | Show config and service state |
| `agent telegram enable [chat]` | Enable boot/login persistence |
| `agent telegram disable` | Disable boot/login persistence |
| `agent telegram doctor` | Check local requirements |

## Remote Control

Users in the connected chat can send these commands:

| Command | Effect |
|---------|--------|
| `stop` | Abort the current turn |
| `status` | Show model, usage, context stats |
| `compact` | Trigger context compaction |


## Storage Layout

Everything lives under `~/.pi/agent/chat/`:

```text
~/.pi/agent/chat/
├── config.json
├── cache/
├── memory.md                             # Simple durable memory
├── SYSTEM.md                             # Host environment modification log
├── skills/                               # Reusable skills
├── secrets/                              # Runtime secrets from chat_request_secret
└── accounts/<account>/
    └── channels/<channel>/
        ├── channel.jsonl
        ├── .lock
        └── channel/
            └── incoming/
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
