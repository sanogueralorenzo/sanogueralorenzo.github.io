# Harness

Harness is a minimal Rust agent runtime inspired by Pi.

The first goal is not to rebuild Pi. The first goal is to keep the smallest useful agent loop:

```text
input -> queue -> session log -> model step -> optional tool -> model step -> final reply
```

The design constraints are:

- simple: one runtime loop, one job at a time, explicit state
- reliable: append-only session events before and after irreversible work
- fast: no network server, TUI, Telegram, plugin loader, or VM boundary in the core loop
- focused: adapters depend on the runtime; the runtime does not know about adapters

## Current Shape

```text
harness/
  Cargo.toml
  src/
    main.rs
    agent/
      mod.rs
      runtime.rs
      session.rs
      model.rs
      apis/
        mod.rs
        openai_completions.rs
        openai_responses.rs
      providers/
        mod.rs
        dry_run.rs
      tools.rs
```

## Run

```shell
cargo run --manifest-path harness/Cargo.toml -- run "hello"
cargo run --manifest-path harness/Cargo.toml -- run "please run pwd"
```

By default, runs append JSONL events to:

```text
harness/.state/default.jsonl
```

Use a different session log with:

```shell
cargo run --manifest-path harness/Cargo.toml -- run --session /tmp/harness.jsonl "hello"
```

The default provider is `dry-run`, which is deterministic and does not call a network API. To run the real provider-backed loop, use the OpenAI provider:

```shell
OPENAI_API_KEY=... \
cargo run --manifest-path harness/Cargo.toml -- run --provider openai "what directory are you in?"
```

Optional environment:

```text
HARNESS_MODEL       default: gpt-4o-mini
HARNESS_OPENAI_API  default: openai-completions
HARNESS_BASE_URL    default: https://api.openai.com/v1
```

The OpenAI provider currently supports the `openai-completions` API adapter, which uses chat completions with JSON-schema function tools. The `openai-responses` adapter exists as a module boundary and returns an explicit not-implemented error until it is ported.

This follows Pi's split between provider and API:

- provider: the vendor or account surface, for example `openai`
- API adapter: the wire protocol, for example `openai-completions` or `openai-responses`

The runtime persists the assistant tool call, runs the local Rust tool, persists the matching tool result, then continues the model loop.

## Validate

```shell
cargo test --manifest-path harness/Cargo.toml
```

## Provider Direction

Providers and API adapters live behind the `ModelClient` contract. Providers choose an API adapter, and adapters own protocol-specific request/response conversion. Keep each API adapter in its own module, add one at a time, and verify tool-call continuation before exposing it through the CLI.

The intended order is:

- OpenAI completions
- OpenAI responses
- Anthropic Messages
- Google Gemini

## Next Pieces

- Add control commands: `stop`, `status`, `new`, `compact`.
- Add a Telegram adapter that submits jobs and streams final replies after the runtime contract is stable.
