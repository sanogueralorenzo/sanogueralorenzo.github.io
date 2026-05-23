# Intent Specification Draft

Intent is a typed workflow language for agents that need to operate across tools, memory, trust boundaries, and verification gates.

This draft defines the minimum coherent language surface for an implementation prototype. It is not a complete grammar. It is the contract that examples, runtime design, and later tooling should converge on.

## Design Target

Intent programs describe work that may span minutes, hours, or days. A program is expected to be inspectable before execution, resumable after interruption, and auditable after completion.

The language treats these concepts as first-class:

- User intent.
- Tool capabilities.
- Trust policy.
- Scoped memory.
- Typed side effects.
- Uncertainty.
- Verification.
- Provenance.

## Compilation Model

An Intent source file compiles into an execution graph.

Each graph contains:

- A `goal` node describing the requested outcome.
- `context` nodes describing readable sources.
- `capability` nodes describing allowed effects.
- `step` nodes from the `plan`.
- `check` nodes from `verify` and `invariant` blocks.
- `approval` nodes for human gates.
- `checkpoint` nodes for resumability.
- `provenance` edges linking outputs to evidence.

The runtime may schedule independent steps concurrently, but it must preserve declared dependencies, approval gates, and effect ordering.

## Source Shape

```intent
package examples.checkout

goal "ship checkout fix" {
  context repo("./")

  capability file {
    read path: "./src/**"
    write path: "./src/**"
    write path: "./test/**"
  }

  capability shell {
    run command: "npm test"
    run command: "npm run lint"
  }

  memory session {
    retain summaries until goal_complete
    retain evidence until 30d
  }

  plan {
    step inspect_failure -> Finding
    step patch_checkout(input: Finding) -> Patch
    step verify_patch(input: Patch) -> Verified<Patch>
  }

  verify {
    require shell("npm test").exit_code == 0
    require shell("npm run lint").exit_code == 0
  }

  invariant {
    deny secret_write
    deny unrelated_file_write
  }
}
```

## Type Families

Intent has ordinary data types and agent-specific types.

Ordinary types:

- `String`
- `Bool`
- `Int`
- `Float`
- `List<T>`
- `Map<K, V>`
- `Record`

Agent-specific types:

- `Goal`
- `Context<T>`
- `Capability<E>`
- `Effect<I, O>`
- `Step<I, O>`
- `Finding`
- `Evidence<T>`
- `Assumption<T>`
- `Decision<T>`
- `Verified<T>`
- `Checkpoint<T>`
- `Provenance<T>`

## Uncertainty Types

Agent work often depends on incomplete evidence. Intent should make that visible in the type system.

```intent
type MaybeKnown<T> =
  | Known<T>
  | Assumed<T>
  | Unknown<T>
  | NeedsHuman<T>
```

Rules:

- `Known<T>` may flow into verification and final output.
- `Assumed<T>` must be declared with rationale and confidence.
- `Unknown<T>` cannot satisfy a required value.
- `NeedsHuman<T>` suspends the graph until a decision is supplied.

Example:

```intent
assume package_manager: Assumed<String> {
  value "npm"
  confidence 0.78
  because evidence("package-lock.json exists")
}
```

## Effect Types

Every side effect has an input type, output type, capability requirement, and provenance record.

```intent
effect ShellExec(command: String) -> ShellResult
  requires capability shell.run(command)
  records stdout, stderr, exit_code, duration
```

The checker rejects effects that do not match declared capabilities.

## Trust Policy

Trust is scoped to principals and zones.

```intent
trust {
  principal agent "codex"
  principal human "owner"

  zone local_repo trusted_for read, write
  zone public_web untrusted
  zone secrets restricted

  require human("owner") before effect GitPush
  deny untrusted_content -> shell.command
}
```

The runtime must treat untrusted content as data, not instructions, unless an explicit trust transition allows it.

## Memory

Memory is scoped by lifecycle and purpose.

```intent
memory project {
  retain summaries until 90d
  retain raw_logs until goal_complete
  erase on request
}
```

Memory cannot silently widen scope. A session memory item cannot become project memory without an explicit promotion step that records provenance.
Step-local `memory read`, `memory write`, and `memory cite` statements make
memory provenance explicit in the execution graph instead of hiding it in step
text.

## Verification

Verification is a completion gate, not a best-effort convention.

```intent
verify {
  require tests("npm test").passed
  require typecheck("npm run typecheck").passed
  require no_policy_violations
  require all_outputs_cited
}
```

A goal cannot complete while required verification is failing, missing, or stale relative to the final effect graph.

## Runtime States

Each step moves through a small state machine:

```text
pending -> ready -> running -> succeeded
                         |-> failed
                         |-> waiting_for_human
                         |-> cancelled
```

Failures may be retried only when the step declares retry policy and the effect is safe to repeat or has an idempotency key.

## Completion

A goal is complete only when:

- Every required step succeeded or was explicitly waived.
- Every required verification passed after the final relevant effect.
- Every approval gate was satisfied.
- Every output has provenance; when the goal requires cited output or denies
  uncited external claims, the final step must cite retained memory evidence
  backed by an earlier write to the same memory target and key.
- No invariant is violated.
- The final state was checkpointed; when the goal requires
  `final_state_checkpointed` or requires `checkpointed_final_state`, the final
  step must declare a checkpoint that can act as the resume boundary. When the
  goal denies `uncheckpointed_irreversible_effect`, every irreversible effect
  must be followed by a checkpoint before completion.
