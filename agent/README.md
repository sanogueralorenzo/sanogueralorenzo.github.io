# Agent

Agent is a small local AI coding agent for real machines.

It is the direction for the current `harness/` experiment: keep the useful Pi-shaped core, but make it easier to understand, install, run, and extend.

## Goal

Build the fastest useful local coding agent:

```text
user input -> durable session -> model step -> tool calls -> tool results -> final reply
```

The agent should be able to read files, edit code, run shell commands, call model providers, save every step to disk, and resume cleanly after a reboot.

## Product Shape

The project should become a single practical binary:

```shell
agent run "fix this bug"
agent status
agent stop
agent login
agent chat telegram
agent install-service
agent doctor
```

The long-term Raspberry Pi story is:

1. install one binary
2. log in once to the model account/subscription
3. enable chat/remote access
4. give the agent full local-machine access
5. reboot safely without losing state

## Core Runtime

The core runtime is intentionally small:

```text
queue
session log
context builder
model client interface
tool registry
runtime loop
event stream
control commands
```

The runtime owns:

- accepting user jobs/messages
- loading and resuming sessions
- building model context from session history
- calling a model through an abstract provider interface
- executing requested tools through an abstract tool registry
- appending every important step to durable JSONL state
- cancellation, retry, status, and continuation
- emitting lifecycle events for UIs and chat adapters

The runtime does **not** own:

- Telegram-specific logic
- TUI/web UI rendering
- OpenAI/Anthropic/Gemini HTTP details
- browser automation implementation
- install/bootstrap logic
- account login UX
- plugin marketplaces

Those pieces attach around the runtime.

## Minimal Agent Loop

The heart of the agent should stay understandable:

```text
while not done:
  context = session.to_model_context()
  step = model.step(context, tool_schemas)

  append assistant output

  for each tool call:
    append tool call
    result = tools.call(tool call)
    append tool result

  if no tool calls:
    finish with final reply
```

If the process dies in the middle, the append-only session log should explain what happened and allow recovery.

## Boundaries

Agent should be split into separable layers:

```text
agent/
  runtime/      durable model/tool execution loop
  providers/    OpenAI, Anthropic, Gemini, local models
  tools/        read, write, edit, bash, grep, find, web, browser
  adapters/     CLI, Telegram, TUI, HTTP, daemon
  install/      service setup, bootstrap, doctor, backup/restore
```

Adapters depend on the runtime. The runtime should not depend on adapters.

Providers depend on the model interface. The runtime should not know provider wire protocols.

Tools expose schemas and callable functions. The runtime should not care whether a tool is native Rust, shell-based, MCP, browser automation, or remote.

## First Milestones

1. Keep `harness/` working as the prototype for the runtime loop.
2. Rename or reshape the useful parts into `agent/` once the boundary is clear.
3. Support local coding tools: `read`, `write`, `edit`, `bash`, `grep`, `find`, `ls`.
4. Support OpenAI through a provider adapter.
5. Add control commands: `status`, `stop`, `new`, `compact`.
6. Add a daemon/queue mode.
7. Add Telegram as an adapter, not as part of the core.
8. Add installer/service commands for Raspberry Pi reboot recovery.

## Design Principles

- Be obvious to users: this is an AI coding agent, not an abstract framework.
- Keep the runtime boring, durable, and inspectable.
- Prefer one binary and plain files over servers and hidden state.
- Append state before and after irreversible work.
- Make tools reusable outside this agent when possible.
- Keep web/chat/UI/login as adapters around the core, not inside it.
- Optimize for fast local iteration and safe reboot recovery.

## Relationship To Harness

`harness/` is the current experimental extraction of the Pi agent loop.

`agent/` is the product direction: the same core idea, named and shaped for people who want a local AI coding agent they can install, run, and trust.
