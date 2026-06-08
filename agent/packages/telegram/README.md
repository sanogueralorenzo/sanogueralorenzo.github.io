# Agent Telegram

A Telegram bridge for a local agent session.

This package intentionally runs with **host access by default**: remote Telegram turns use the same local filesystem and process access as the local agent process.

## Quick Start

```bash
# Configure Telegram account and trusted chat
agent telegram login

# Start the persistent bridge
agent telegram start
```

### Requirements

- A Telegram bot token
- Optional for voice transcription: Python with `faster-whisper` available to the worker

## Features

- One Telegram DM/group at a time
- Direct host-machine access for coding tools
- Persistent chat storage across sessions
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
| `agent telegram login` | Configure the Telegram bot and trusted chat |
| `agent telegram run` | Run the Telegram worker in the foreground |
| `agent telegram start` | Enable and start the persistent Telegram service |
| `agent telegram stop` | Stop and disable the Telegram service |
| `agent telegram status` | Show config and service state |
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
├── secrets/                              # Runtime secrets received from Telegram
└── accounts/<account>/
    └── channels/<chat>/
        ├── channel.jsonl
        ├── .lock
        └── channel/
            └── incoming/
```

The agent's actual working directory is the local process cwd. The chat storage paths above are regular host paths and can be read/written directly.

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

## Agent Execution

The standalone daemon calls the local coding agent in print mode for each queued Telegram turn:

```text
Telegram message -> local queue/log -> pi --print -> Telegram reply
```

The agent runs with normal host coding tools such as `read`, `write`, `edit`, and `bash`.

## Security Model

This package is for trusted Telegram chats only.

A connected chat can drive an agent with local host access. Configure the trusted Telegram chat carefully. Do not connect untrusted groups or users.

## License

MIT
