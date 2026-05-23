# Intent

Intent is a sketch for an agent-first programming language.

Most programming languages are built around instructions: compute this value, call this function, mutate this state. Intent starts from a different premise: agents need a language for goals, context, permissions, memory, uncertainty, verification, and accountable side effects.

The core idea is simple:

```intent
goal "ship checkout fix" {
  context repo("./")
  capability file(read, write)
  capability shell(run: ["npm test", "npm run lint"])
  budget time: 30m

  plan {
    inspect failing_tests
    patch minimal
    verify with ["npm test", "npm run lint"]
    require human_approval before git_push
  }

  invariant {
    never_commit secrets
    never_modify unrelated_files
    explain external_calls
  }
}
```

## Why It Exists

Agents do not only execute code. They interpret intent, gather context, call tools, make assumptions, recover from errors, and decide when they need human input.

Those behaviors are usually hidden inside prompts, frameworks, logs, or orchestration glue. Intent makes them part of the program.

## Language Primitives

- `goal`: the outcome the agent is trying to reach.
- `context`: bounded sources of truth such as files, tickets, docs, logs, chats, or prior runs.
- `capability`: explicit permissions for files, shell commands, network calls, secrets, deploys, and external tools.
- `plan`: resumable steps with stable inputs and outputs.
- `effect`: typed side effects such as `FileWrite`, `ShellExec`, `HttpCall`, `GitCommit`, or `Deploy`.
- `memory`: persisted state that must be scoped, inspectable, and erasable.
- `uncertainty`: first-class assumptions, confidence, and human-decision points.
- `verify`: tests, assertions, screenshots, policy checks, and runtime checks.
- `rollback`: compensating actions for risky or irreversible effects.
- `provenance`: traceability from output back to commands, files, docs, and assumptions.

## Design Principles

1. Goals are explicit.
2. Permissions are typed.
3. Side effects are visible.
4. Plans are resumable.
5. Verification is mandatory.
6. Assumptions are declared.
7. Human approval is a language feature, not a comment.
8. Memory has scope and lifecycle.
9. Failure is recoverable by default.
10. Every result has provenance.

## What The Future Version Might Look Like

Intent programs could compile into execution graphs that agent runtimes can inspect before running. A runtime would be able to answer:

- What is this agent allowed to touch?
- What tools can it call?
- What state can it remember?
- Which steps are reversible?
- Which checks must pass before completion?
- Which actions require human approval?
- Why did it make this decision?

In that world, agents become less like opaque chat loops and more like auditable, typed collaborators.

## Example: Research Task

```intent
goal "compare model providers" {
  context web(domains: ["openai.com", "anthropic.com", "google.com"])
  capability web(read)
  budget time: 20m

  plan {
    collect official_docs
    extract pricing, limits, model_families
    compare on ["latency", "cost", "context", "tool_use"]
    cite sources
  }

  verify {
    require sources >= 3
    require no_uncited_claims
  }
}
```

## Example: Code Change

```intent
goal "add csv export" {
  context repo("./")
  capability file(read, write)
  capability shell(run: ["npm test", "npm run typecheck"])

  plan {
    inspect feature_boundary
    implement smallest_change
    update tests
    verify with ["npm test", "npm run typecheck"]
  }

  invariant {
    no_any_types
    no_unrelated_refactors
  }
}
```

## Open Questions

- Should Intent be a standalone language, a DSL, or an intermediate representation?
- Should it target existing runtimes such as Temporal, Kubernetes, GitHub Actions, or custom agent sandboxes?
- How strict should the type system be around uncertainty and side effects?
- Can prompts be compiled into Intent safely?
- What does package management mean when capabilities are part of the dependency graph?

## First Prototype

The smallest useful prototype would include:

1. A parser for `goal`, `context`, `capability`, `plan`, `verify`, and `invariant`.
2. A static checker that rejects undeclared side effects.
3. A runtime that executes steps through tool adapters.
4. A checkpoint store for resumability.
5. A verification gate that must pass before a goal can complete.

The language should begin as a constraint system around agents, then grow toward a full programming model.
