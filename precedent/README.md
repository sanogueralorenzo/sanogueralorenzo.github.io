# Precedent

Precedent is a passive hook layer for agent-readiness.

It observes normal coding-agent conversations, turns repeated failures and successful moves into repo-specific precedent, and injects that precedent back into future conversations only when it is relevant.

The goal is simple: every agent run should make the repository easier for the next agent to change safely.

## Core Idea

Modern coding agents fail in repeatable ways:

- They use the wrong setup or test command.
- They miss implicit service contracts.
- They edit too broadly.
- They add abstractions that do not fit the codebase.
- They misunderstand feature boundaries.
- They repeat mistakes that previous agents already made.

Precedent watches those traces, extracts the reusable lesson, and compiles it into a durable repository artifact. It does not replace the coding agent. It sits around the agent as a memory and guardrail layer.

## Reference Inspiration

Precedent combines four ideas from existing agent work:

- [Karpathy-inspired skills](https://github.com/multica-ai/andrej-karpathy-skills): explicit assumptions, simplicity, surgical edits, and goal-driven verification.
- [Hermes Agent](https://github.com/NousResearch/hermes-agent): self-improving skills, persistent memory, scheduled automation, subagents, and trace compression.
- [Clawpatch](https://github.com/openclaw/clawpatch): semantic repo mapping, persisted findings, resumable patch attempts, strict schemas, and one-finding-at-a-time validation.
- [Thermo-nuclear code quality review](https://github.com/cursor/plugins/blob/main/cursor-team-kit/skills/thermo-nuclear-code-quality-review/SKILL.md): harsh structural review, code-judo simplification, and explicit rejection of spaghetti growth.

Precedent's twist is the hook loop: it learns during ordinary work and injects the smallest useful precedent into the next ordinary conversation.

## Hook Layer

Precedent runs as a set of passive hooks around a coding agent:

- `conversation.observe`: captures user intent, agent assumptions, tool calls, command output, diffs, retries, and final outcome.
- `context.before_turn`: injects only the precedent relevant to the current repo slice, task type, command, or failure pattern.
- `diff.after_edit`: checks whether the agent is drifting into known bad patterns such as broad edits, wrong-layer logic, or accidental abstraction growth.
- `validation.after_run`: records tests, typechecks, linters, command failures, and runtime evidence.
- `review.after_feedback`: converts review comments into structured failure modes.
- `outcome.after_task`: decides whether the trace should create, update, or retire precedent.

The hook layer should be quiet by default. It should not flood the conversation with memory. It should inject one or two high-confidence precedents when they are likely to change the outcome.

## Product Loop

1. Observe a normal agent conversation.
2. Record prompts, assumptions, tool calls, diffs, test failures, review comments, retries, and outcomes.
3. Map the trace to semantic repo slices.
4. Classify repeated failures and successful moves.
5. Compile the cheapest durable precedent artifact:
   - `SKILL.md` for reusable agent procedure.
   - `AGENTS.md` or repo instructions for project-specific behavior.
   - Tests or checks for broken behavior.
   - Contract files for implicit assumptions.
   - Error, script, or documentation patches when the repo confused the agent.
   - Structural review rules when agent changes create complexity.
6. Re-run the same or weaker baseline agent against the original task and a held-out task.
7. Promote the artifact only if the rerun improves success rate, retries, token use, time-to-green, or diff quality.
8. Inject promoted precedent into future conversations when the same repo slice or task pattern appears.

## Precedent Artifacts

Each precedent is small, auditable, and tied to evidence:

```json
{
  "id": "prec_webhook_payload_nullability",
  "scope": "feature:webhooks",
  "trigger": "task mentions webhook payload handling",
  "lesson": "Webhook payload fields from external providers may be absent; preserve existing nullable parsing helpers.",
  "artifact": "skill",
  "paths": ["features/webhooks", "webhooks/providers"],
  "source_trace": "runs/2026-05-23-add-webhook-handler.json",
  "evidence": ["review-comment: missed nullable field", "test: webhook payload fixture failed"],
  "injection": "Before editing webhook handlers, inspect existing nullable payload helpers and reuse them.",
  "promotion": {
    "baseline_failures": 2,
    "rerun_failures": 0,
    "token_delta": "-38%"
  }
}
```

Precedent should prefer specific, local lessons over broad advice. A good precedent sounds like something a senior maintainer would say in review before the mistake happens.

## MVP

Build a local CLI first, then a GitHub app:

- `precedent init`: creates `.precedent/`.
- `precedent observe`: ingests an agent trace, PR diff, validation log, or review thread.
- `precedent compile`: turns repeated failure modes into candidate artifacts.
- `precedent inject`: returns the relevant precedent for the current task context.
- `precedent context`: exports stable agent-ready precedent context.
- `precedent hook`: reads a passive hook event and returns an insertable context block.
- `precedent replay`: reruns a baseline agent task with and without injected precedent.
- `precedent explain`: audits why a precedent was promoted or rejected.
- `precedent run`: wraps a validation command and records the result as a session hook.
- `precedent manifest`: emits the machine-readable hook contract for an agent runtime.
- `precedent report`: prints before/after metrics.

The first version should support one repo, five seeded tasks, one baseline coding agent, and three failure classes:

- Wrong setup or test command.
- Overbroad edit against the wrong repo slice.
- Missed implicit contract visible in tests, types, or review feedback.

## Prototype CLI

This repository includes a small dependency-free prototype:

```shell
node precedent/bin/precedent.mjs init
node precedent/bin/precedent.mjs observe --trace precedent/examples/webhook-trace.json
node precedent/bin/precedent.mjs inject --task "add another webhook handler" --scope feature:webhooks
node precedent/bin/precedent.mjs context --task "add another webhook handler" --scope feature:webhooks
echo '{"schema_version":"precedent.v1","hook":"context.before_turn","task":"add another webhook handler","scope":"feature:webhooks","changedFiles":["features/webhooks/providers/stripe.ts"]}' | node precedent/bin/precedent.mjs hook
node precedent/bin/precedent.mjs hook --event-file precedent/examples/before-turn-event.json
node precedent/bin/precedent.mjs hook before-turn --task "add another webhook handler" --scope feature:webhooks --changed-files features/webhooks/providers/stripe.ts
node precedent/bin/precedent.mjs replay --case precedent/examples/replay/webhook-case.json --trace-out /tmp/precedent-webhook-replay-trace.json
node precedent/bin/precedent.mjs explain --id prec_webhook_replay_boundary
printf '%s\n' '{"schema_version":"precedent.v1","hook":"validation.after_run","sessionId":"demo","command":"pnpm test:webhooks","exitCode":1,"stderr":"nullable payload test failed"}' | node precedent/bin/precedent.mjs hook
node precedent/bin/precedent.mjs run --session demo -- pnpm test:webhooks
node precedent/bin/precedent.mjs manifest --runtime generic
node precedent/bin/precedent.mjs observe --session demo
node precedent/bin/precedent.mjs report
```

The prototype models the hook loop with local state in `.precedent/`:

- `observe` is the passive hook ingesting an agent trace.
- `inject` is the before-turn hook returning relevant precedent.
- `context` is the preferred runtime-facing export: it returns `schema_version: "precedent.context.v1"`, an insertable `contextBlock`, injection metadata, suppression metadata, and the source inputs used for ranking.
- `hook` reads a hook event from stdin or `--event-file`, logs the event, and returns an insertable `contextBlock` for normal agent conversation context.
- `hook before-turn` is the flag-based conversation hook shape: it scores task text, repo scope, and changed files, logs the hook event, and returns a compact `Precedent:` block plus structured injection data.
- Every injection includes `matchReasons`, so a runtime can show why Precedent injected memory instead of treating it as opaque prompt context.
- Session hooks suppress a precedent after it has already been injected once in the same session; pass `"allowRepeat": true` only when a runtime intentionally wants repeated context.
- `explain` returns the promotion reason, source trace or session, replay delta, evidence, matching scope and paths, and recent injection history for one precedent id.
- Hook events can carry `sessionId`. Precedent appends them to `.precedent/sessions/<sessionId>.jsonl`, so ordinary conversations can be observed without a handcrafted trace file.
- `run --session <id> -- <command>` wraps a normal validation command, streams stdout/stderr, preserves the command exit code, and records a `validation.after_run` event automatically.
- `manifest` emits the argv commands, fields, output fields, timeout, and fail-open policy a runtime needs to wire Precedent in.
- `observe --session <id>` compiles the recorded hook events into a trace under `.precedent/traces/`.
- `replay` runs baseline and rerun commands, stores command evidence under `.precedent/replays/`, and can emit a promotion-ready trace for `observe`.
- `report` shows the local precedent ledger.

`observe` has a promotion gate: a candidate precedent is recorded as an event but is not injected later unless it has concrete evidence and measured replay improvement where `baseline_failures` is greater than `rerun_failures`. When a trace contains verified replay evidence, `observe` prefers the replay metrics over inline claim metrics.

Promotion is idempotent. Re-observing the same promoted precedent updates the existing ledger row instead of appending duplicates, merges unique evidence, preserves the original `created_at`, refreshes `updated_at` only when the record changes, and keeps `.precedent/precedents.jsonl` sorted by precedent id for deterministic diffs.

All JSON inputs use an explicit v1 schema marker. `observe`, `hook`, and `replay` reject missing or unknown schema versions with an exact field error.

Security behavior is intentionally small and deterministic: before Precedent writes hook events, sessions, traces, replay artifacts, ledgers, or context injections, it redacts common secrets with typed markers such as `[REDACTED:bearer_token]`, `[REDACTED:openai_key]`, `[REDACTED:github_token]`, `[REDACTED:slack_token]`, `[REDACTED:connection_string_password]`, and `[REDACTED:credential]`. `run` still streams the wrapped command's stdout/stderr unchanged to the caller and preserves the exact exit code, but the stored command output is redacted.

Example runtime manifest:

```json
{
  "schema_version": "precedent.manifest.v1",
  "runtime": "generic",
  "stateDir": ".precedent",
  "hooks": {
    "context.before_turn": {
      "command": ["node", "precedent/bin/precedent.mjs", "context", "--state-dir", ".precedent", "--task-file", "$TASK_FILE", "--scope", "$SCOPE", "--changed-files", "$CHANGED_FILES", "--session", "$SESSION_ID", "--format", "json"],
      "injectFrom": "contextBlock",
      "timeoutMs": 1500,
      "failurePolicy": "fail_open"
    }
  }
}
```

Example explain response:

```json
{
  "ok": true,
  "id": "prec_webhook_replay_boundary",
  "promotionStatus": "promoted",
  "promotionReason": "verified replay improved from 1 baseline failure(s) to 0 rerun failure(s)",
  "source": {
    "traceId": "webhook-replay-improves-replay",
    "sessionId": null,
    "replayId": "webhook-replay-improves",
    "replayPath": "/tmp/precedent/replays/webhook-replay-improves/replay.json"
  },
  "replay": {
    "baselineFailures": 1,
    "rerunFailures": 0,
    "failureDelta": 1
  },
  "matching": {
    "scope": "feature:webhooks",
    "trigger": "task mentions webhook handler, webhook payload, or provider event",
    "artifact": "skill",
    "paths": ["features/webhooks", "webhooks/providers"]
  },
  "injections": []
}
```

Example event hook response:

```json
{
  "ok": true,
  "hook": "context.before_turn",
  "contextBlock": "Precedent:\n- For webhook changes in this repo: run pnpm test:webhooks, keep provider-specific logic inside the webhook provider boundary, and reuse existing nullable payload helpers.",
  "suppressedInjections": [],
  "injections": [
    {
      "id": "prec_webhook_provider_boundary",
      "score": 16,
      "matchReasons": [
        {
          "type": "text_overlap",
          "score": 7,
          "terms": ["webhook", "provider", "nullable"]
        },
        {
          "type": "scope_match",
          "score": 5,
          "scope": "feature:webhooks"
        },
        {
          "type": "path_match",
          "score": 4,
          "file": "features/webhooks/providers/stripe.ts",
          "path": "features/webhooks"
        }
      ],
      "scope": "feature:webhooks",
      "artifact": "skill",
      "injection": "For webhook changes in this repo: run pnpm test:webhooks, keep provider-specific logic inside the webhook provider boundary, and reuse existing nullable payload helpers.",
      "sourceTrace": "2026-05-23-add-webhook-handler"
    }
  ]
}
```

There is also a runnable hook-loop example that uses temporary state and leaves the repo clean:

```shell
node precedent/examples/hook-loop/run.mjs
```

The example sends two `context.before_turn` events through `precedent hook`: the first returns an empty `contextBlock`, the failed trace is observed and promoted, then the follow-up turn receives a compact `Precedent:` block.

It is intentionally small. The next build step is wiring these commands to real agent traces and PR review events.

## Session Hook Events

The JSON hook API is the shape a normal coding-agent runtime would call while a conversation is happening.

Before the agent starts a turn:

```json
{
  "schema_version": "precedent.v1",
  "hook": "context.before_turn",
  "sessionId": "demo",
  "task": "add webhook handler",
  "scope": "feature:webhooks",
  "changedFiles": ["features/webhooks/providers/stripe.ts"]
}
```

After validation runs:

```json
{
  "schema_version": "precedent.v1",
  "hook": "validation.after_run",
  "sessionId": "demo",
  "command": "pnpm test:webhooks",
  "exitCode": 1,
  "stderr": "nullable payload test failed"
}
```

After edits:

```json
{
  "schema_version": "precedent.v1",
  "hook": "diff.after_edit",
  "sessionId": "demo",
  "changedFiles": ["features/webhooks/providers/stripe.ts", "README.md"]
}
```

After the task ends:

```json
{
  "schema_version": "precedent.v1",
  "hook": "outcome.after_task",
  "sessionId": "demo",
  "success": false,
  "retries": 2,
  "tokenEstimate": 4100,
  "notes": "Agent used the wrong test command and missed nullable payload handling."
}
```

Then compile the session into an observable trace:

```shell
node precedent/bin/precedent.mjs observe --session demo
```

This makes the hook layer useful during ordinary agent conversations: hooks quietly collect context, validation, diff, and outcome evidence; promotion still requires concrete evidence plus measured replay improvement before any precedent becomes injectable.

## Schema Contracts

Every JSON file or hook event passed into Precedent must include:

```json
{
  "schema_version": "precedent.v1"
}
```

Minimal trace input:

```json
{
  "schema_version": "precedent.v1",
  "id": "2026-05-23-add-webhook-handler",
  "task": "add a webhook handler",
  "scope": "feature:webhooks",
  "failures": ["wrong test command"]
}
```

Minimal replay case:

```json
{
  "schema_version": "precedent.v1",
  "id": "webhook-replay",
  "baseline": { "command": "false" },
  "rerun": { "command": "true" },
  "precedent": {
    "id": "prec_webhook_boundary",
    "scope": "feature:webhooks",
    "trigger": "task mentions webhook handler",
    "lesson": "Use the webhook provider boundary.",
    "artifact": "skill",
    "injection": "For webhook changes, stay inside the provider boundary."
  }
}
```

## Killer Demo

Task: add a webhook handler.

The baseline agent fails because it uses the wrong test command, invents an abstraction that does not match the repo, and misses a payload nullability contract.

Precedent ingests the trace, writes a repo-specific skill, adds a small contract check, and patches the setup command docs.

Later, in a normal conversation, a user asks another agent to add a different webhook event. Before the agent edits code, Precedent injects:

> For webhook changes in this repo: use `pnpm test:webhooks`, reuse the existing nullable payload parser, and keep provider-specific logic inside `features/webhooks/providers`.

The same weak agent reruns the task and lands a smaller passing PR with fewer retries and fewer tokens.

## Design Constraints

- Passive first: observe and inject before attempting autonomous edits.
- Evidence-backed: every precedent must link to a trace, diff, review, command, or validation record.
- Relevance-gated: inject only when task context matches the precedent scope.
- Small artifacts: prefer one precise skill, check, contract, or instruction over broad memory dumps.
- Forward-only: retire stale precedent when replay shows it no longer improves outcomes.
- Model-agnostic: work with Codex, Cursor, Claude, Hermes-style agents, or any agent that can emit traces.

## Why It Matters

Most agent products try to make the model smarter.

Precedent makes the repository smarter. It creates a compounding memory of what agents should and should not do in that codebase.

The durable asset is not a dashboard. It is repo-specific engineering judgment encoded as executable precedent.
