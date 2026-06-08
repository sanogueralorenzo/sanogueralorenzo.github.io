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
HARNESS_CACHE_RETENTION default: short; values: short, long, none
HARNESS_MODEL_INPUTS optional comma list: text or text,image
HARNESS_MODEL_REASONING optional boolean override for model reasoning metadata
```

The OpenAI provider supports two API adapters:

- `openai-completions`: chat completions with JSON-schema function tools
- `openai-responses`: Responses API input items, function tools, and function-call output continuation

For OpenAI adapters, the harness derives a stable opaque session ID from the session log path. With cache retention `short`, it sends that ID as `prompt_cache_key` and as `session_id` / `x-client-request-id` headers. With `long`, it also sends `prompt_cache_retention: 24h`. With `none`, it omits all prompt cache fields and session affinity headers. If `HARNESS_CACHE_RETENTION` is unset, `PI_CACHE_RETENTION=long` is also honored.

Tool call IDs follow Pi's OpenAI Responses replay shape. Responses tool calls are persisted as `call_id|item_id` when the provider returns both fields. When replaying into Responses, unsafe or long foreign item IDs are normalized into bounded `fc_<hash>` IDs; when replaying into chat completions, only the normalized `call_id` is sent.

This follows Pi's split between provider and API:

- provider: the vendor or account surface, for example `openai`
- API adapter: the wire protocol, for example `openai-completions` or `openai-responses`

OpenAI construction resolves into one Pi-shaped provider/model config before the adapter is built. The config keeps the provider id, API adapter, base URL, model id, input capabilities, reasoning metadata, API key, and cache retention together. The harness still only exposes `dry-run` and `openai`; it does not import Pi's broader provider registry, custom `models.json`, fuzzy resolver, or OAuth flow yet.

The runtime persists the assistant tool call, runs the local Rust tool, persists the matching tool result, then continues the model loop.

## Runtime Loop

The runtime loop follows Pi's agent-session shape while keeping the harness synchronous and small:

- runtime state tracks whether the agent is running, cancellation, current turn index, and retry attempt
- separate steering and follow-up queues mirror Pi's interrupt-vs-after-current-run behavior
- lifecycle events cover agent start/end, queue updates, turn start/end, message start/end, tool execution start/end, retry start/end, cancellation, and compaction hook checks
- retry policy uses bounded attempts and exponential backoff for transient provider/network errors
- an auto-compaction hook check exists, but full compaction is intentionally deferred until the session log has Pi-style compaction entries

The current model contract returns complete model steps instead of streamed token deltas, so streaming parity is represented by lifecycle events and queue semantics. Token-level streaming can be added behind the same runtime event surface without changing the core loop.

## Coding Tools

Harness exposes the Pi coding tool set through a single cwd-bound Rust registry:

- `read`: read text files with `offset` / `limit`, head truncation, and truncation details; supported image files are detected and recorded in tool details for image-capable adapter replay
- `bash`: execute `/bin/sh -lc` commands in the process cwd with optional timeout, Unix process-group cleanup, tail truncation, exit code details, and temp-file persistence for truncated full output
- `edit`: apply exact text replacements to one file; each `oldText` must match exactly once and edits must not overlap. Like Pi, it accepts legacy `oldText` / `newText`, JSON-string `edits`, BOM/line-ending preservation, and fuzzy matching for common quote/dash/space differences.
- `write`: create parent directories and write/overwrite a file; file mutations are serialized per path
- `grep`: search file contents through `rg`, respecting `.gitignore`, with match limits and long-line truncation
- `find`: search file paths through `fd`, respecting `.gitignore`, with result limits
- `ls`: list directory entries alphabetically, including dotfiles, with `/` suffixes for directories

Relative paths resolve against the cwd where the harness process starts. Absolute paths are allowed, `~` is expanded, and a leading `@` is stripped for pasted file paths, matching Pi's local-machine tool behavior. Tool result details are stored in the JSONL session log, while model adapters send the plain text output back to the model.

`grep` resolves `rg`; `find` resolves `fd` or `fdfind`. Resolution order is explicit env path, harness-managed cache, then `PATH`. If a tool is still missing, harness downloads the matching GitHub release archive into `harness/.state/tools`, extracts the binary, and reuses it on later runs. `HARNESS_RG_PATH`, `HARNESS_FD_PATH`, and `HARNESS_FDFIND_PATH` can point to explicit executables. `HARNESS_TOOLS_DIR` changes the cache directory. Set `HARNESS_OFFLINE=1` or `PI_OFFLINE=1` to disable downloads and return a clear missing-tool error. Other tools use the Rust standard library and `/bin/sh`.

## Validate

```shell
cargo test --manifest-path harness/Cargo.toml
```

## Provider Direction

Providers and API adapters live behind the `ModelClient` contract. Providers resolve a model config, choose an API adapter, and adapters own protocol-specific request/response conversion. Keep each API adapter in its own module, add one at a time, and verify tool-call continuation before exposing it through the CLI.

The intended order is:

- OpenAI completions
- OpenAI responses
- Anthropic Messages
- Google Gemini

## Next Pieces

- Add control commands: `stop`, `status`, `new`, `compact`.
- Add a Telegram adapter that submits jobs and streams final replies after the runtime contract is stable.
