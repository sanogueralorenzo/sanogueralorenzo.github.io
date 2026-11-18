# Development

Agent is built on Pi Durable. Run commands from `tools/agent` with Node 26+.

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

Router and dispatcher use GPT-6 Luna or Claude Haiku 5.5 with reasoning disabled, Gemini 3.5 Flash-Lite at minimal, or Grok 4.7 at low. Gemini and Grok cannot disable reasoning. Other providers use the selected model at low. This mapping applies with fast mode on or off.

Model pickers use a curated lineup because Pi's catalog has no release dates: GPT-6.1 Sol, GPT-6 Astra, and GPT-6 Luna; Claude Fable 5.1 and Opus/Sonnet/Haiku 5.5; Gemini 4 Argon, 3.8 Flash, and 3.5 Flash-Lite; and Grok 4.7.

Conversations and workers use native web search with OpenAI, Anthropic, xAI, and the listed Gemini models. The router, dispatcher, and reply suggestions do not receive search tools.

## Local state

- `~/.agent/durable.sqlite`: state and transcripts.
- `~/.agent/suggestions.db`: saved reply suggestions.
- `~/.agent/auth.json`: provider credentials.
- `~/.agent/provider.json`: selected provider and model.
- `~/.agent/fast-mode.json`: per-provider fast preferences.
- `~/.agent/settings.json`: installation ID managed by Pi.
