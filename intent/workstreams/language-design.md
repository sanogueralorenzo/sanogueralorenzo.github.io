# Intent Language Design

Intent is an agent-first typed workflow language. It describes what an agent
should accomplish, what information it may trust, what side effects it may
perform, how uncertainty is represented, and which checks must pass before a
goal is complete.

The language is designed to be concrete enough for a parser, static checker,
and resumable runtime without hiding agent behavior inside prompts.

## Goals

- Make goals, assumptions, permissions, and effects explicit.
- Let runtimes inspect a workflow before execution.
- Reject undeclared side effects at check time.
- Represent uncertainty as typed data instead of prose.
- Make human approval, verification, and recovery part of the program.
- Keep workflows resumable through stable step inputs, outputs, and checkpoints.

## File Shape

Intent source files use the `.intent` extension. A file contains a package
header, imports, declarations, and one or more goals.

```intent
package github.checkout

import std.git
import std.fs
import std.shell

capability repo_files = fs.access(root: "./", mode: ReadWrite)
capability tests = shell.allow(commands: ["npm test", "npm run typecheck"])

goal ship_checkout_fix(input: Issue) -> PullRequest
  uses repo_files, tests
  effects FileRead, FileWrite, ShellExec, GitCommit
{
  ...
}
```

## Syntax Conventions

Intent uses declarations followed by optional clauses and a braced block.
Newlines separate declarations and statements. Commas separate fields and
arguments. Semicolons are not used.

```intent
declaration =
  package_decl
  | import_decl
  | type_decl
  | capability_decl
  | effect_decl
  | policy_decl
  | goal_decl

goal_decl =
  "goal" identifier "(" parameters ")" "->" type goal_clause* block

goal_clause =
  "uses" capability_list
  | "effects" effect_list
  | "requires" expression

step_decl =
  "step" identifier "(" parameters ")" "->" type step_clause* block

step_clause =
  "effects" effect_list
  | "timeout" duration
  | "retry" retry_policy
```

Identifiers use `snake_case` for values, functions, steps, and capabilities;
`PascalCase` for types, effects, and tagged union cases; and dot-separated
lowercase names for packages and modules. Comments start with `#` and run to
the end of the line.

Expressions include literals, names, field access, function calls, records,
lists, tagged union constructors, `let` bindings, `if` expressions, `match`
expressions, and effectful calls. Control flow is expression-oriented, but
effectful calls are only legal inside steps whose effect set permits them.

## Declarations

Top-level declarations define reusable values, types, capabilities, effects,
policies, and goals.

```intent
type Issue = {
  id: String,
  title: String,
  body: String,
  labels: List<String>
}

type PullRequest = {
  url: Url,
  branch: String,
  commit: Sha
}

capability repo_read = fs.access(root: "./", mode: Read)
capability repo_write = fs.access(root: "./", mode: ReadWrite)

effect GitCommit = effect {
  reversible: false,
  approval: HumanRequired,
  fields: { message: String, files: List<Path> }
}

policy no_secrets {
  deny FileWrite where content.matches(secret_pattern)
  deny GitCommit where files.any(path.matches(".env*"))
}
```

Declarations are immutable. A name may be declared once per module. Imports
must be explicit, and unqualified name collisions are rejected.

## Goal Syntax

A goal is the main executable unit.

```intent
goal <name>(<inputs>) -> <output>
  uses <capabilities>
  effects <effect-set>
  requires <preconditions>
{
  context { ... }
  state { ... }
  plan { ... }
  verify { ... }
  recover { ... }
}
```

Goal fields:

- `input`: typed values supplied by the caller or runtime.
- `output`: the value produced when the goal completes.
- `uses`: capabilities available to this goal.
- `effects`: side effects the goal may perform.
- `requires`: static or runtime preconditions.
- `context`: bounded sources of truth.
- `state`: persisted checkpoint state.
- `plan`: ordered, resumable workflow blocks.
- `verify`: completion gates.
- `recover`: compensation or escalation behavior.

## Blocks

Blocks are scoped. Values declared inside a block are not visible outside it
unless returned, emitted, or assigned to goal state.

### Context Block

The `context` block declares trusted inputs and their freshness rules.

```intent
context {
  repo = fs.repo("./") freshness Current
  issue = github.issue(input.id) freshness MaxAge(10m)
  docs = web.sources(domains: ["docs.github.com"]) freshness MaxAge(1d)
}
```

Context values are read-only by default. Writes must go through an effect.

### State Block

The `state` block declares resumable persisted state.

```intent
state {
  inspected: Bool = false
  patch_files: Set<Path> = {}
  test_result: Maybe<ShellResult> = none
}
```

State writes are checkpointed after each completed step. State types must be
serializable.

### Plan Block

The `plan` block contains executable steps.

```intent
plan {
  step inspect_repo() -> Inspection
    effects FileRead
  {
    read repo.files(["package.json", "src/**", "test/**"])
    return inspect_changes()
  }

  step patch(inspection: Inspection) -> Patch
    effects FileRead, FileWrite
  {
    let patch = create_patch(inspection)
    write patch.files
    state.patch_files = patch.files
    return patch
  }

  step run_tests(patch: Patch) -> ShellResult
    effects ShellExec
  {
    return shell.run("npm test")
  }
}
```

Steps are the unit of retry, timeout, checkpointing, and provenance. A runtime
may resume from the last completed step if inputs and declared context versions
are still valid.

### Verify Block

The `verify` block must pass before a goal can return.

```intent
verify {
  require state.patch_files.size > 0
  require test_result.exit_code == 0
  require no_policy_violations(no_secrets)
}
```

Verification expressions are pure and cannot perform side effects.

### Recover Block

The `recover` block handles failures by typed error class.

```intent
recover {
  on ShellFailed(command: "npm test") retry max 2
  on PolicyDenied escalate HumanReview(reason: error.message)
  on IrreversibleEffectFailed escalate HumanReview(reason: error.message)
}
```

Recovery actions are also effect-checked.

## Type System

Intent uses a structural, static type system with effect checking. Type
inference is local to expressions, but public declarations must include
explicit types.

### Primitive Types

- `Bool`
- `Int`
- `Decimal`
- `String`
- `Bytes`
- `Duration`
- `Timestamp`
- `Path`
- `Url`
- `Sha`
- `Json`

### Type Forms

```intent
List<T>
Set<T>
Map<K, V>
Maybe<T>
Result<T, E>
Stream<T>
Task<T, Effects>
Assumed<T>
Evidence<T>
Confidence<T>
Review<T>
```

Records are structural:

```intent
type Finding = {
  path: Path,
  line: Maybe<Int>,
  message: String,
  severity: Severity
}
```

Unions are tagged:

```intent
type Severity = Low | Medium | High | Critical

type ReviewDecision =
  | Approved { reviewer: String, at: Timestamp }
  | Rejected { reviewer: String, reason: String }
  | NeedsInfo { question: String }
```

Functions are pure unless their return type carries effects:

```intent
fn summarize(findings: List<Finding>) -> String
fn run_tests(command: String) -> Task<ShellResult, ShellExec>
```

## Uncertainty Types

Uncertainty must be represented in values that the checker and runtime can
inspect.

```intent
type Assumed<T> = {
  value: T,
  reason: String,
  confidence: ConfidenceScore,
  expires: Maybe<Timestamp>,
  evidence: List<EvidenceRef>
}

type Evidence<T> = {
  value: T,
  source: EvidenceRef,
  observed_at: Timestamp
}

type Confidence<T> = {
  value: T,
  score: ConfidenceScore
}

type Review<T> =
  | Pending { request: String }
  | Approved { value: T, reviewer: String, at: Timestamp }
  | Rejected { reason: String, reviewer: String, at: Timestamp }
```

Rules:

- `Assumed<T>` cannot be passed where `T` is required without `confirm`,
  `verify`, or `approve`.
- Values below a goal-defined confidence threshold cannot affect irreversible
  effects.
- `Review<T>` must be resolved before use in a step that requires `T`.
- Evidence references must point to declared context or prior step output.

Example:

```intent
let target_file: Assumed<Path> = assume(
  value: "src/checkout.ts",
  reason: "Issue title names checkout flow",
  confidence: 0.72,
  evidence: [issue.body]
)

let confirmed_file: Path = confirm target_file by fs.exists(target_file.value)
```

## Effect Types

Effects describe all observable interactions outside pure evaluation.

```intent
effect FileRead = effect {
  reversible: true,
  approval: None,
  fields: { paths: List<Path> }
}

effect FileWrite = effect {
  reversible: true,
  approval: Optional,
  fields: { paths: List<Path> }
}

effect ShellExec = effect {
  reversible: false,
  approval: Optional,
  fields: { command: String, timeout: Duration }
}

effect Deploy = effect {
  reversible: false,
  approval: HumanRequired,
  fields: { environment: String, version: String }
}
```

Effect rules:

- Every step declares its effect set.
- A step effect must be included in the parent goal effect set.
- A goal effect must be backed by a capability in `uses`.
- Irreversible effects require verification gates and recovery behavior.
- Human-required effects pause execution until a typed approval is present.

Common standard effects:

- `FileRead`
- `FileWrite`
- `ShellExec`
- `HttpCall`
- `SecretRead`
- `GitBranch`
- `GitCommit`
- `GitPush`
- `IssueUpdate`
- `PullRequestCreate`
- `Deploy`

## Modules And Packages

A package is a named collection of modules with a manifest.

```intent
package intent.example.checkout

requires intent >= "0.1"

dependency std.fs >= "0.1"
dependency std.git >= "0.1"
dependency std.shell >= "0.1"

export goal ship_checkout_fix
export type Issue
export type PullRequest
```

Package rules:

- Package names are reverse-domain or organization scoped.
- Dependencies must declare required capabilities and effects.
- Public goals, types, policies, and capabilities must be exported.
- Capability requirements are part of dependency resolution.
- A package cannot widen a dependency capability without redeclaring it.

## Static Checks

The checker rejects programs when:

- A step performs an undeclared effect.
- A goal uses an effect without a matching capability.
- An assumed value flows into an irreversible effect without confirmation.
- A verification block is missing for a goal with side effects.
- A recovery path is missing for an irreversible effect.
- A context source has no freshness rule.
- A public declaration lacks an explicit type.
- A persisted state value is not serializable.

## Examples

### Code Change Goal

```intent
package examples.code_change

import std.fs
import std.shell

type ChangeRequest = {
  summary: String,
  paths: List<Path>
}

type ChangeResult = {
  files: List<Path>,
  tests: ShellResult
}

capability repo = fs.access(root: "./", mode: ReadWrite)
capability npm = shell.allow(commands: ["npm test"])

goal apply_small_change(input: ChangeRequest) -> ChangeResult
  uses repo, npm
  effects FileRead, FileWrite, ShellExec
{
  context {
    files = fs.files(input.paths) freshness Current
  }

  state {
    changed: List<Path> = []
    tests: Maybe<ShellResult> = none
  }

  plan {
    step edit() -> List<Path>
      effects FileRead, FileWrite
    {
      let patch = derive_patch(files, input.summary)
      write patch
      state.changed = patch.paths
      return patch.paths
    }

    step test(paths: List<Path>) -> ShellResult
      effects ShellExec
    {
      let result = shell.run("npm test", timeout: 5m)
      state.tests = some(result)
      return result
    }
  }

  verify {
    require state.changed.size > 0
    require state.tests.value.exit_code == 0
  }

  recover {
    on ShellFailed(command: "npm test") retry max 1
  }
}
```

### Research Goal With Evidence

```intent
package examples.research

import std.web

type Comparison = {
  answer: String,
  citations: List<Url>
}

capability official_docs = web.access(
  domains: ["openai.com", "docs.github.com"],
  mode: Read
)

goal compare_tools(topic: String) -> Comparison
  uses official_docs
  effects HttpCall
{
  context {
    sources = web.search(topic, domains: official_docs.domains)
      freshness MaxAge(7d)
  }

  plan {
    step collect() -> Evidence<List<WebPage>>
      effects HttpCall
    {
      return evidence(web.fetch(sources.urls), source: sources)
    }

    step synthesize(pages: Evidence<List<WebPage>>) -> Comparison
      effects None
    {
      return summarize_with_citations(pages.value)
    }
  }

  verify {
    require output.citations.size >= 2
    require output.answer.has_no_uncited_claims
  }
}
```

### Human Approval Before Push

```intent
package examples.release

import std.git

type ReleaseInput = {
  version: String,
  branch: String
}

capability git_remote = git.access(remote: "origin", mode: Push)

goal push_release(input: ReleaseInput) -> Url
  uses git_remote
  effects GitPush
{
  context {
    branch = git.branch(input.branch) freshness Current
  }

  plan {
    step request_approval() -> Review<Bool>
      effects None
    {
      return request_review("Push release " + input.version + "?")
    }

    step push(approval: Review<Bool>) -> Url
      effects GitPush
    {
      let approved: Bool = require_approved(approval)
      return git.push(branch.name, approved)
    }
  }

  verify {
    require output.host == "github.com"
  }

  recover {
    on GitPushFailed escalate HumanReview(reason: error.message)
  }
}
```
