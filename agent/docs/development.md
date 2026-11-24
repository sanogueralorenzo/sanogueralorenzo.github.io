# Development

Agent uses Pi Durable for tasks, tools, and transcripts. Run commands from `agent` with Node 26+.

## Checks

```bash
npm run check
npm run test:tasks
npm run test:delegation
npm run test:providers
npm run test:composer
```

The composer tests require Google Chrome.

## Workflow

Home routing chooses conversations in message order and hands off immediately to a separate dispatch queue for each conversation. Dispatch decisions stay ordered within a conversation and run concurrently across conversations; messages sent inside a conversation bypass routing. Home routing has Pi's read-only filesystem tools to locate project folders.

The dispatcher starts independent requests concurrently and records prerequisites for dependent follow-ups. Each request runs a coordinator against its own history snapshot, delegates execution to workers, and publishes its completed answer atomically to the shared conversation. Waiting for workers never blocks independent requests.

Workers have coding, shell, computer-use, and delegation tools, with separate conversations and private working notes. Up to eight execution model requests run concurrently, with additional capacity reserved for dispatch and Home routing. Task dependencies, completion receipts, conversations, and queues survive service restarts. The UI keeps tools and reasoning private and identifies which request each answer belongs to. Interrupted unsafe tools are reported instead of replayed.

## Models

The CLIs handle authentication and model calls. Codex app-server and Claude Code replace their default system prompts with Agent's role instructions. Antigravity runs an Agent-defined custom agent with default prompt components and inherited customizations disabled. Codex Code Mode exposes the role's tools as native dynamic tools. Claude Code and Antigravity use structured responses for Agent tool requests. Pi Durable executes Agent tool calls and restores context from the durable transcript when a turn reopens.

Routing and dispatch use the selected CLI’s lightweight model. Conversations and workers can use CLI web search. Reply suggestions, routing, and dispatch do not receive web search tools.

## Local state

- `~/.agent/durable.sqlite`: state and transcripts.
- `~/.agent/suggestions.db`: saved reply suggestions.
- `~/.agent/provider.json`: selected provider and model.
- `~/.agent/fast-mode.json`: per-provider fast preferences.
