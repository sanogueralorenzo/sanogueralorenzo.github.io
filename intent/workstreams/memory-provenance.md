# Intent Memory and Provenance

Intent needs memory that agents can use without becoming opaque or unbounded. This note defines scoped memory, retention, erasure, summaries, evidence, provenance, citations, checkpointing, and syntax for an agent-first typed workflow language.

## Goals

- Make every persisted fact belong to an explicit scope.
- Separate compact working summaries from durable evidence.
- Preserve enough provenance to explain outputs, decisions, and side effects.
- Make retention and erasure enforceable by static checks and runtime policy.
- Make checkpoints resumable without hiding mutable global state.

## Non-Goals

- Define a storage engine.
- Define privacy law compliance by jurisdiction.
- Preserve full transcripts forever.
- Allow untyped agent memory outside declared workflow state.

## Core Model

Memory is typed state declared inside a `goal` or imported from a trusted scope. Provenance is a typed graph that connects outputs to the evidence, summaries, tool calls, assumptions, approvals, and checkpoints that produced them.

```intent
goal "ship billing fix" {
  context repo("./")
  capability file(read, write)
  capability shell(run: ["npm test"])

  memory session Scratch {
    retain until goal_complete
    erase on request
  }

  memory project DecisionLog {
    retain for 180d
    summarize every 20 events
    evidence keep references_only
  }

  plan {
    inspect failing_tests -> memory.session.test_findings
    patch minimal citing memory.session.test_findings
    verify with ["npm test"]
    checkpoint "after verification"
  }
}
```

## Memory Scopes

Intent defines memory scope as part of the type. A runtime must reject reads or writes across scopes unless the workflow declares an explicit import, promotion, or citation.

| Scope | Lifetime | Typical Use | Default Access |
| --- | --- | --- | --- |
| `step` | One step execution | Tool output, temporary parse results | Current step only |
| `session` | One goal run | Working notes, unresolved findings | Current goal only |
| `checkpoint` | Resume boundary | Step inputs, outputs, effect ids | Runtime and current goal |
| `task` | Logical task across retries | Decisions, human approvals, retry state | Same task id |
| `project` | Repository or workspace | Stable conventions, architecture decisions | Declared project goals |
| `user` | User-controlled long-term scope | Preferences and standing instructions | Requires explicit consent |
| `org` | Organization-controlled scope | Policies, shared procedures | Requires policy grant |

Scope names are not strings. They are type constructors:

```intent
memory session Scratch {
  key test_findings: List<Finding>
  key touched_files: Set<Path>
}

memory project DecisionLog {
  key decisions: AppendLog<Decision>
}
```

The static checker enforces:

- A `step` value cannot be cited after the step unless promoted to `session` or attached to a checkpoint.
- A `session` value cannot survive goal completion unless promoted to `task`, `project`, `user`, or `org`.
- A wider scope cannot depend on a narrower scope without a provenance edge and retention policy.
- `user` and `org` scopes require named consent or policy capability.

## Retention

Retention is mandatory for scopes wider than `step`. A memory declaration must state when data expires and what remains after compaction.

```intent
memory task ReleaseState {
  retain until task_closed + 30d
  compact to summary every 50 events
  evidence keep hashes_and_locations
}
```

Retention policies:

- `retain until goal_complete`
- `retain until task_closed + Duration`
- `retain for Duration`
- `retain while cited_by(OutputId)`
- `retain forever requires approval("retention")`

Compaction policies:

- `compact none`: keep full values until expiry.
- `compact to summary`: keep a typed summary with citations to retained evidence.
- `compact to digest`: keep hashes, metadata, and provenance edges only.
- `compact delete`: remove value and all derived summaries unless another retained value cites it.

Retention is transitive. If an output is retained and cites evidence, the runtime must retain either the evidence itself or a replacement proof allowed by `evidence keep`.

## Erasure

Erasure is a first-class effect. It must be auditable without retaining erased content.

```intent
erase memory.user.preference where subject == "email_address" {
  reason user_request
  replace_with tombstone
  preserve provenance digest
}
```

Erasure modes:

- `delete`: remove value and derived summaries.
- `tombstone`: replace value with an erased marker containing id, type, erasure time, and actor.
- `redact fields`: remove selected fields while keeping the rest of the value.
- `rotate secret`: invalidate the stored secret reference and replace it with a new handle.

Rules:

- Erasure must invalidate summaries that incorporated erased content unless they can be recomputed from non-erased evidence.
- Citations to erased evidence remain as tombstone citations with no content.
- Checkpoints that contain erased values become non-resumable unless the workflow declares a safe recomputation path.
- Runtime logs must record erasure metadata, not erased payloads.

## Summaries vs Evidence

Intent treats summaries and evidence as different types.

```intent
type Evidence<T> {
  id: EvidenceId
  source: Source
  content: T
  hash: Digest
}

type Summary<T> {
  id: SummaryId
  content: T
  cites: Set<EvidenceId | SummaryId>
  confidence: Confidence
}
```

Evidence is source material: file snapshots, command output, API responses, human approvals, screenshots, logs, messages, and documents. A summary is an agent-authored compression of evidence.

Rules:

- A summary cannot be used as sole proof for an irreversible effect.
- A summary must cite at least one evidence node or earlier summary.
- Any claim emitted outside scratch memory must be traceable to evidence or an explicit assumption.
- Evidence can be retained as full content, content address, external location, or tombstone.
- Summaries must record model/runtime identity and prompt/tool context needed for audit.

Example:

```intent
evidence test_output: ShellOutput from shell("npm test")

summary failures: TestFailureSummary {
  from test_output
  keep fields ["failed_tests", "error_messages", "command", "exit_code"]
}

effect FileWrite("src/billing.ts") {
  reason "Fix failing invoice rounding test"
  cites failures
}
```

## Provenance Graph

Provenance is an append-only directed acyclic graph for a workflow run. Nodes are typed. Edges are typed. The runtime may store it in any backend, but Intent semantics treat it as part of execution.

Node types:

- `Goal`: declared workflow objective.
- `Context`: repo, ticket, document, chat, web page, database, or prior run.
- `Step`: declared plan step.
- `ToolCall`: shell command, file read, HTTP call, model call, browser action, or connector call.
- `Evidence`: captured source material.
- `Summary`: compressed interpretation.
- `Assumption`: declared uncertain claim.
- `Decision`: selected path with rationale.
- `Approval`: human or policy approval.
- `Effect`: file write, commit, deploy, message send, issue update, or erasure.
- `Checkpoint`: resumable state boundary.
- `Output`: final answer, artifact, report, PR, release, or created item.

Edge types:

- `declares`: goal to memory, capability, invariant, or plan.
- `reads`: step or tool call to context or memory.
- `writes`: step or tool call to memory.
- `observes`: evidence to source.
- `summarizes`: summary to evidence or summary.
- `assumes`: step, decision, or output to assumption.
- `decides`: decision to candidate inputs and selected path.
- `approves`: approval to effect or retention policy.
- `produces`: step or tool call to evidence, summary, effect, or output.
- `cites`: effect or output to evidence, summary, decision, assumption, or approval.
- `checkpoints`: checkpoint to memory and completed effects.
- `erases`: erasure effect to memory value, evidence, summary, or checkpoint.

Minimum graph invariant:

```intent
verify provenance {
  require every Output cites Evidence | Summary | Decision | Assumption
  require every Effect cites Evidence | Decision | Approval
  require no cycles
  require no live citation to erased_content
}
```

## Citations

Citations are typed references, not display-only links. A citation can point to retained content, an external stable location, a digest, or a tombstone.

```intent
output Report {
  claim "The failing behavior is covered by invoice.spec.ts"
    cite file("test/invoice.spec.ts", lines: 42..67)

  claim "The fix passed validation"
    cite command("npm test", exit: 0)
}
```

Citation forms:

- `file(path, lines?)`
- `command(command, exit, range?)`
- `http(url, method, status, body_hash?)`
- `ticket(id, fields?)`
- `message(channel, timestamp)`
- `approval(id)`
- `memory(scope.key, version)`
- `checkpoint(id)`
- `digest(hash, algorithm)`
- `tombstone(id, erased_at)`

Citation rules:

- User-visible claims need citations unless they are clearly marked as assumptions or recommendations.
- Effects need citations that explain why the effect was valid.
- Citation ranges must be stable against file version changes by including file digest or commit id.
- Citations to summaries must expose the summary's own citations.

## Checkpointing

A checkpoint captures enough typed state to resume deterministically after interruption. It is not a hidden heap dump.

```intent
checkpoint "after patch" {
  include memory.session.test_findings
  include effect FileWrite("src/billing.ts")
  include evidence command("npm test", exit: 1)
  resume at verify
  retry budget 2
}
```

Checkpoint contents:

- Completed step ids.
- Declared memory values needed by later steps.
- Idempotency keys for completed effects.
- Tool call ids and captured evidence.
- Pending approvals.
- Retry counters and timeout state.
- Provenance frontier: the node ids later work may cite.

Rules:

- Every irreversible effect must be checkpointed after it runs and before the
  next irreversible effect or completion.
- Resuming from a checkpoint must not repeat a completed effect unless the effect declares idempotency.
- Checkpoints inherit retention from the widest memory value they include.
- Erasure can make a checkpoint partial or invalid; the runtime must report that before resume.

## Example Syntax

This example shows scoped memory, summaries, evidence retention, provenance checks, checkpointing, and citation-backed output.

```intent
goal "triage flaky checkout test" {
  context repo("./")
  context issue("PAY-1842")

  capability file(read, write: ["test/**", "src/checkout/**"])
  capability shell(run: ["npm test -- checkout"])

  memory session TriageMemory {
    key failures: List<TestFailure>
    key hypothesis: Optional<Hypothesis>
    retain until goal_complete
    compact delete
  }

  memory task CheckoutTaskMemory {
    key decisions: AppendLog<Decision>
    retain until task_closed + 30d
    compact to summary every 25 events
    evidence keep hashes_and_locations
  }

  plan {
    step reproduce {
      let raw = shell("npm test -- checkout")
      evidence checkout_output = raw.stdout
      summary parsed_failures from checkout_output into memory.session.failures
      checkpoint "reproduced failure"
    }

    step diagnose {
      assume "The failing assertion reflects checkout timeout behavior"
        confidence medium
        cite memory.session.failures

      decide "Patch timeout handling instead of retrying assertion" {
        cite file("src/checkout/timeout.ts")
        write memory.task.decisions
      }
    }

    step patch {
      edit file("src/checkout/timeout.ts") {
        reason "Make timeout cancellation explicit"
        cite memory.task.decisions.latest
      }
      checkpoint "patch written"
    }

    step verify {
      let result = shell("npm test -- checkout")
      evidence verify_output = result.stdout
      require result.exit_code == 0
      checkpoint "verified"
    }
  }

  output "Checkout flake triaged and fixed" {
    cite memory.task.decisions.latest
    cite command("npm test -- checkout", exit: 0)
  }

  verify provenance {
    require no_uncited_effects
    require no_session_memory_after goal_complete
    require every summary cites evidence
  }
}
```

## Static Checks

The compiler should reject workflows that:

- Read undeclared memory.
- Write to a wider scope without a retention policy.
- Promote memory without a provenance edge.
- Complete a goal while `session` memory has retained live content.
- Emit an output claim with no citation or assumption.
- Use a summary as the only citation for an irreversible effect.
- Resume from a checkpoint whose required memory has expired or been erased.
- Retain evidence forever without explicit approval.

## Runtime Responsibilities

The runtime must:

- Assign stable ids to memory values, evidence, summaries, decisions, effects, and checkpoints.
- Record provenance edges as execution happens.
- Enforce scope access at read and write time.
- Apply retention and erasure policies deterministically.
- Surface citation chains in final outputs and audit views.
- Refuse completion when required provenance or verification is missing.
- Make checkpoint resume behavior explicit before executing resumed steps.

## Open Questions

- Should `user` and `org` memory be available by default only through read-only summaries?
- Should summaries include enough prompt context to reproduce them exactly or only to audit them?
- How should Intent represent conflicting evidence inside the provenance graph?
- Should retention policies be checked at compile time only, runtime only, or both?
- What is the minimum portable provenance export format?
