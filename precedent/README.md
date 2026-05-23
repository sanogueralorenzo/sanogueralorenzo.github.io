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
- `precedent replay`: reruns a baseline agent task with and without injected precedent.
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
node precedent/bin/precedent.mjs report
```

The prototype models the hook loop with local state in `.precedent/`:

- `observe` is the passive hook ingesting an agent trace.
- `inject` is the before-turn hook returning relevant precedent.
- `report` shows the local precedent ledger.

It is intentionally small. The next build step is wiring these commands to real agent traces and PR review events.

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
