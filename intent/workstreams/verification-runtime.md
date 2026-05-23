# Intent Verification and Runtime Semantics

This note defines the first concrete runtime model for Intent as an agent-first typed workflow language. It specifies how a goal compiles into an execution graph, how steps run, how verification gates completion, and how retries, cancellation, checkpoints, and invariants keep agent behavior auditable.

## Runtime Model

An Intent program compiles into a typed execution graph.

```intent
goal "ship checkout fix" {
  context repo: RepoRef = repo("./")

  capability files: FileAccess = file(read, write, paths: ["src/**", "test/**"])
  capability tests: ShellAccess = shell(run: ["npm test", "npm run typecheck"])

  input ticket: TicketRef
  output patch: GitDiff

  plan {
    step inspect(ticket) -> findings: FindingSet
    step implement(findings) -> patch: GitDiff
    step verify(patch) -> report: VerificationReport
  }

  check no_unrelated_files(patch)
  check tests_pass(report)

  invariant never_commit_secrets
  invariant effects_within_capabilities

  complete when patch.applied && report.status == "passed"
}
```

The graph is the runtime contract. It is not a suggestion to the agent. Every runnable node, input, output, effect, check, and completion rule must be represented in the graph before execution starts.

## Execution Graph

The graph contains these node types:

- `Goal`: the root outcome, declared inputs, declared outputs, budgets, and completion criteria.
- `Context`: read-only or read-write sources of truth such as repositories, tickets, logs, docs, chats, and prior checkpoints.
- `Capability`: typed permission to perform effects through runtime adapters.
- `Step`: a resumable unit of agent work with typed inputs, outputs, effects, checks, and retry policy.
- `Check`: a deterministic or bounded nondeterministic verification operation.
- `Invariant`: a rule that must hold before and after every effect and at every checkpoint.
- `Effect`: a typed external action such as `FileWrite`, `ShellExec`, `HttpCall`, `GitCommit`, `Deploy`, or `HumanApproval`.
- `Checkpoint`: persisted step state and provenance used for resume, audit, and recovery.
- `Completion`: a final gate that decides whether the goal is done.

Edges are typed data dependencies or control dependencies:

- `requires`: a node cannot start until required nodes complete.
- `produces`: a node emits a typed value consumed by later nodes.
- `authorizes`: a capability permits a specific effect shape.
- `verifies`: a check validates a value, step, effect, or goal.
- `guards`: an invariant constrains execution before the guarded action may continue.
- `recovers`: a failure edge defines the next step after a retry budget is exhausted.

The compiler rejects graphs with cycles unless the cycle is declared as a bounded loop with a variant that must make progress.

## Types

Intent types describe agent-visible values and side-effect boundaries.

```intent
type VerificationReport {
  status: "passed" | "failed" | "blocked"
  checks: List<CheckResult>
  evidence: List<ArtifactRef>
}

type RetryPolicy {
  max_attempts: Int
  backoff: Duration
  retry_when: List<FailureClass>
}
```

The minimum runtime type families are:

- Value types: `String`, `Int`, `Bool`, `Duration`, `List<T>`, `Map<K,V>`, records, enums, and tagged unions.
- Reference types: `FileRef`, `RepoRef`, `TicketRef`, `ArtifactRef`, `SecretRef`, and `CheckpointRef`.
- Effect types: `FileRead`, `FileWrite`, `ShellExec`, `NetworkRead`, `NetworkWrite`, `GitWrite`, `Deploy`, and `HumanApproval`.
- Result types: `Ok<T>`, `Err<E>`, `Async<T>`, `CheckResult`, `StepResult`, and `GoalResult`.
- Failure types: `Transient`, `Validation`, `CapabilityDenied`, `InvariantViolation`, `CheckFailed`, `Timeout`, `Cancelled`, and `Blocked`.

Effects are values before they are actions. A step proposes an effect, the runtime checks it against capabilities and invariants, then the adapter executes it.

## Step Lifecycle

Each step moves through a fixed lifecycle:

1. `Planned`: the step exists in the compiled graph.
2. `Ready`: all dependencies are satisfied and inputs are available.
3. `Running`: the runtime has acquired leases and budgets.
4. `EffectPending`: the step requested an external effect.
5. `EffectApplied`: the adapter completed the effect and recorded evidence.
6. `Checking`: step checks and relevant invariants are running.
7. `Completed`: outputs passed type checks and verification gates.
8. `Retrying`: the failure matches retry policy and budget remains.
9. `Blocked`: the step requires human input or an unavailable dependency.
10. `Cancelled`: cancellation was requested and cleanup completed.
11. `Failed`: retry and recovery options are exhausted.

A step may write outputs only when it reaches `Completed`. Intermediate observations must be stored as checkpoint evidence, not as final outputs.

## Step Declaration

```intent
step implement(findings: FindingSet) -> patch: GitDiff {
  uses files
  retry max_attempts: 2 backoff: 10s when [Transient, Timeout]
  timeout 15m

  effects {
    FileRead(paths: ["src/**", "test/**"])
    FileWrite(paths: ["src/**", "test/**"])
  }

  check patch_is_minimal(patch)
  check no_generated_secrets(patch)
}
```

A step declaration has:

- Typed inputs and outputs.
- Capability references through `uses`.
- Allowed effect shapes.
- Optional timeout, retry policy, cancellation behavior, and checkpoint policy.
- Step-local checks.
- Provenance requirements for outputs.

The runtime rejects any effect not declared by the step and authorized by a capability.

## Checks

Checks are executable verification rules. They return `CheckResult`.

```intent
check tests_pass(report: VerificationReport) -> CheckResult {
  require report.status == "passed"
  evidence report.evidence
}

check shell_command_passes(cmd: ShellCommand) -> CheckResult {
  run cmd
  pass when exit_code == 0
}
```

Checks have these semantics:

- A check must be side-effect free unless it declares a verification effect such as `ShellExec` or `NetworkRead`.
- A check must produce evidence: a value, artifact, command transcript, source citation, screenshot, log excerpt, or human decision.
- A failed required check prevents the guarded step or goal from completing.
- An advisory check records risk but does not block completion.
- A skipped check must include a typed reason: `Unavailable`, `NotApplicable`, `PermissionDenied`, or `Superseded`.

Required checks default to blocking.

## Invariants

Invariants are always-on rules. They are evaluated before execution, before and after every effect, after every retry, at checkpoint time, and before completion.

```intent
invariant effects_within_capabilities {
  for effect in proposed_effects {
    require exists capability where capability.authorizes(effect)
  }
}

invariant never_commit_secrets {
  require no_secret_material in [FileWrite, GitWrite, ArtifactRef]
}
```

Invariant failures are not normal check failures. They immediately stop the current step and mark the goal `Failed` unless a declared recovery edge can restore the invariant.

Core runtime invariants:

- Every effect must be authorized by at least one capability.
- Every step output must match its declared type.
- Every final output must have provenance.
- Checkpoint state must be serializable and scoped to the goal.
- Human approval must be explicit before irreversible effects.
- Cancellation must stop new effects from starting.
- Completion requires all required checks to pass or be explicitly waived by an authorized human decision.

## Effects and Capabilities

Capabilities are typed grants. Effects are typed requests.

```intent
capability repo_files: FileAccess = file(
  read,
  write,
  paths: ["intent/**"],
  deny: ["**/.env", "**/secrets/**"]
)

effect write_note: FileWrite {
  path: "intent/workstreams/verification-runtime.md"
  content: markdown
}
```

Authorization succeeds only when all of these are true:

- The effect type is permitted by the capability.
- The effect target is within declared scope.
- The effect parameters satisfy capability constraints.
- No invariant rejects the effect.
- Required approvals have been granted.

Adapters execute effects. Adapters must return structured evidence with command, target, timing, exit status, changed artifacts, and error details.

## Retries

Retries are explicit and bounded.

```intent
retry max_attempts: 3 backoff: exponential(2s, max: 30s) when [Transient, Timeout]
```

Retry semantics:

- The first run counts as attempt `1`.
- Only failures matching `retry_when` may retry.
- `Validation`, `CapabilityDenied`, `InvariantViolation`, and `CheckFailed` do not retry by default.
- The runtime writes a checkpoint before each retry.
- A retry must reuse stable inputs unless a recovery edge produces new inputs.
- Non-idempotent effects require an idempotency key or a compensation rule before they can be retried.

A retry cannot hide failure history. All attempts remain part of provenance.

## Cancellation

Cancellation is cooperative at step boundaries and enforced at effect boundaries.

```intent
cancel {
  on request stop_new_effects
  timeout 30s
  cleanup release_locks
  checkpoint current_state
}
```

When cancellation is requested:

- No new effects may start.
- Running adapters receive a cancellation signal.
- The runtime waits until the step reaches a cancellable boundary or the cancellation timeout expires.
- Cleanup effects may run only if declared in `cancel`.
- The final state is `Cancelled` if cleanup succeeds, otherwise `Failed`.

Cancellation does not erase checkpoints or evidence.

## Checkpoints

Checkpoints make workflows resumable and auditable.

```intent
checkpoint after each_step {
  include inputs, outputs, effect_log, check_results, assumptions
  retain 30d
}
```

A checkpoint stores:

- Goal id, graph version, runtime version, and step id.
- Step state and attempt number.
- Typed inputs and completed outputs.
- Proposed, denied, and applied effects.
- Check results and invariant evaluations.
- Evidence artifacts and provenance links.
- Open assumptions and human decisions.
- Retry, timeout, cancellation, and budget state.

Resume semantics:

- The runtime reloads the latest valid checkpoint for the graph version.
- Completed steps are not rerun unless declared `rerunnable`.
- Pending non-idempotent effects are reconciled before continuing.
- Changed source files, context versions, or capability grants may invalidate affected steps.
- If graph migration is unavailable, resume is blocked and requires human decision.

## Completion Criteria

A goal completes only when its `complete when` expression is true and the runtime final gate passes.

```intent
complete when {
  patch.applied
  checks.required.all_passed
  no_open_blockers
  outputs.patch.type == GitDiff
}
```

The final gate verifies:

- All required steps are `Completed`.
- Required checks passed.
- Invariants hold.
- Required outputs exist and match declared types.
- Required evidence is attached.
- No cancellation, unresolved blocker, pending approval, or exhausted budget remains.
- Completion criteria evaluate to true.

The runtime returns `GoalResult`.

```intent
type GoalResult {
  status: "completed" | "failed" | "blocked" | "cancelled"
  outputs: Map<String, Value>
  checks: List<CheckResult>
  evidence: List<ArtifactRef>
  provenance: ProvenanceGraph
}
```

## Failure Semantics

Failures are typed and must be surfaced as data.

```intent
recover CheckFailed from verify {
  step diagnose(report) -> issue: VerificationIssue
  step repair(issue) -> patch: GitDiff
  step verify(patch) -> report: VerificationReport
}
```

Failure handling rules:

- `Blocked` means progress requires human input or an unavailable external dependency.
- `Failed` means declared recovery paths and retries are exhausted.
- `Cancelled` means the user or runtime stopped execution before completion.
- `CapabilityDenied` means the program requested an undeclared or unauthorized effect.
- `InvariantViolation` means the runtime safety contract was broken.

Recovery edges must be explicit. The runtime cannot invent a recovery path that performs new effect types or touches new scopes.

## Provenance

Every output and final claim must trace back to evidence.

```intent
provenance patch {
  from step implement
  evidence [diff, file_reads, check_results]
}
```

Provenance records:

- Which step produced the value.
- Which inputs and context versions were used.
- Which effects changed external state.
- Which checks validated the result.
- Which assumptions were active.
- Which human approvals or waivers were applied.

The provenance graph is part of the `GoalResult`.

## Example: Verification Runtime Flow

```intent
goal "update verification runtime note" {
  context repo: RepoRef = repo("./")

  capability note_file: FileAccess = file(
    read,
    write,
    paths: ["intent/workstreams/verification-runtime.md"]
  )

  output note: FileRef

  plan {
    step inspect_repo() -> style: MarkdownStyle {
      uses note_file
      effects { FileRead(paths: ["intent/README.md"]) }
      check style_detected(style)
    }

    step draft_note(style) -> note: FileRef {
      uses note_file
      effects { FileWrite(paths: ["intent/workstreams/verification-runtime.md"]) }
      check ascii_only(note)
      check repository_ready_markdown(note)
    }

    step verify_note(note) -> report: VerificationReport {
      uses note_file
      effects { FileRead(paths: ["intent/workstreams/verification-runtime.md"]) }
      check includes_sections(note, [
        "Execution Graph",
        "Step Lifecycle",
        "Checks",
        "Invariants",
        "Retries",
        "Cancellation",
        "Checkpoints",
        "Completion Criteria",
        "Example"
      ])
    }
  }

  invariant only_declared_file_written
  invariant ascii_markdown

  complete when report.status == "passed"
}
```

## Minimal Runtime API

A prototype runtime needs a small host interface.

```intent
runtime IntentRuntime {
  compile(program: SourceFile) -> Result<ExecutionGraph, CompileError>
  start(graph: ExecutionGraph, inputs: Map<String, Value>) -> RunId
  resume(run: RunId) -> GoalResult
  cancel(run: RunId, reason: String) -> GoalResult
  checkpoint(run: RunId) -> CheckpointRef
}
```

The runtime must expose graph inspection before execution so humans and policy tools can answer:

- What can this program read or write?
- Which effects are irreversible?
- Which checks block completion?
- Which steps can retry?
- Which state is persisted?
- What evidence will be required at the end?

## Open Design Decisions

- Whether checks should be pure Intent functions, adapter-backed runtime calls, or both.
- Whether graph versions should use structural hashes or package versions.
- How much of provenance should be mandatory for small local workflows.
- Whether human waivers are normal effects or privileged runtime events.
- How to type long-running agent memory without making checkpoints too large.
