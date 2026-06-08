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

## Validate

```shell
cargo test --manifest-path harness/Cargo.toml
```

## Next Pieces

- Replace the demo model with a real provider client.
- Add a Telegram adapter that submits jobs and streams final replies.
- Add control commands: `stop`, `status`, `new`, `compact`.
- Add a tiny TUI only after the runtime contract is stable.
