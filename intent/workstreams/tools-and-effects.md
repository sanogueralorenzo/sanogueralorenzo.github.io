# Intent Tools And Effects

Intent treats every external action as a typed effect. A workflow may reason freely, but it may only touch the outside world through declared capabilities, checked effect signatures, and runtime adapters that enforce the contract.

This note defines the concrete language surface for tool and effect capabilities.

## Goals

- Make side effects visible before a workflow runs.
- Give agents a typed way to ask for tools without hiding permissions in prompts.
- Let runtimes deny, approve, execute, audit, and roll back effects consistently.
- Keep workflow code portable across local shells, hosted sandboxes, CI jobs, and agent platforms.

## Core Model

An Intent program has three layers:

1. `capability` declarations describe what a workflow is allowed to request.
2. `effect` signatures describe typed operations that may change or observe the world.
3. `adapter` bindings connect effect signatures to concrete tools in a runtime.

The checker rejects any effect call that is not covered by an in-scope capability. The runtime rejects any adapter invocation whose resolved arguments exceed the checked capability.

```intent
goal "update release notes" {
  context repo("./")

  capability fs.read(paths: ["CHANGELOG.md", "releases/**"])
  capability fs.write(paths: ["releases/*.md"])
  capability git.commit(paths: ["releases/*.md"])

  use effect fs.read_file
  use effect fs.write_file
  use effect git.commit

  plan {
    let notes = fs.read_file(path: "CHANGELOG.md")
    fs.write_file(path: "releases/next.md", content: notes)
    git.commit(message: "Update release notes", paths: ["releases/next.md"])
  }
}
```

## Capability Declarations

A capability is a permission grant over a named resource family. It is declarative, typed, and statically checkable where possible.

```intent
capability <family>.<action>(<constraints>)
```

Examples:

```intent
capability fs.read(paths: ["src/**", "README.md"])
capability fs.write(paths: ["src/**/*.ts"], max_bytes: 200000)
capability shell.exec(commands: ["npm test", "npm run lint"], timeout: 5m)
capability http.request(methods: ["GET"], domains: ["api.github.com"])
capability secret.read(names: ["GITHUB_TOKEN"], purpose: "github api")
capability git.push(remotes: ["origin"], branches: ["main"], approval: required)
capability deploy.release(targets: ["staging"], approval: required)
```

Capabilities are additive but not ambient. A nested block may narrow capability scope:

```intent
step "format docs" {
  capability fs.write(paths: ["docs/**/*.md"])
  capability shell.exec(commands: ["npm run format:docs"], timeout: 2m)

  shell.exec(command: "npm run format:docs")
}
```

The checker normalizes paths, commands, domains, branch names, and secret names before comparing effect calls against grants. Dynamic values are allowed only when their type carries a proof that the value was derived from an approved source or constrained by a validator.

```intent
let target: Path<"docs/**/*.md"> = select_changed_file()
fs.write_file(path: target, content: body)
```

## Typed Effect Signatures

An effect signature is a typed function declaration with an effect kind, input schema, output schema, denied error variants, approval policy, and optional rollback contract.

```intent
effect fs.write_file(
  path: Path,
  content: String,
  mode: WriteMode = replace
) -> FileWriteResult
  requires fs.write(path)
  denies [PathOutsideGrant, BinaryContentDenied, MaxBytesExceeded]
  rollback fs.restore_file(snapshot: before)
```

Effect signatures are part of the language package, not the adapter implementation. The signature is the contract that a planner, checker, runtime, and audit log all understand.

### Common Effect Types

```intent
type FileWriteResult = {
  path: Path,
  bytes: Int,
  sha256: String,
  before: FileSnapshot?,
  after: FileSnapshot
}

type ShellExecResult = {
  command: String,
  exit_code: Int,
  stdout: String,
  stderr: String,
  duration_ms: Int
}

type HttpResponse<T> = {
  status: Int,
  headers: Map<String, String>,
  body: T,
  request_id: String?
}

type ApprovalDecision = {
  approved: Bool,
  approver: Principal,
  reason: String,
  expires_at: Time?
}
```

### Signature Examples

```intent
effect fs.read_file(path: Path) -> String
  requires fs.read(path)
  denies [PathOutsideGrant, FileMissing, FileTooLarge]

effect shell.exec(command: ShellCommand, env: Map<String, SecretRef> = {}) -> ShellExecResult
  requires shell.exec(command)
  denies [CommandOutsideGrant, TimeoutExceeded, NonZeroExit]
  rollback none

effect http.request<T>(
  method: HttpMethod,
  url: Url,
  headers: Map<String, String> = {},
  body: Json? = null
) -> HttpResponse<T>
  requires http.request(method, url.domain)
  denies [DomainOutsideGrant, MethodOutsideGrant, SecretInUrl, ResponseTooLarge]
  rollback compensating if declared

effect git.commit(message: String, paths: List<Path>) -> GitCommitResult
  requires git.commit(paths)
  denies [PathOutsideGrant, EmptyCommit, DirtyUntrackedDenied]
  rollback git.revert_commit(commit: result.sha)

effect deploy.release(target: DeployTarget, artifact: ArtifactRef) -> DeploymentResult
  requires deploy.release(target)
  approval required
  denies [TargetOutsideGrant, ArtifactUnverified, ApprovalMissing]
  rollback deploy.rollback(target: target, release: result.release_id)
```

## Adapters

Adapters implement effect signatures for a runtime. They are explicit bindings from a language-level effect to a concrete tool, API, binary, service, or sandbox primitive.

```intent
adapter local.fs implements fs {
  effect read_file -> host.read_file
  effect write_file -> host.write_file
}

adapter local.shell implements shell {
  effect exec -> sandbox.exec(
    cwd: context.repo.root,
    network: denied,
    inherit_env: false
  )
}

adapter github.rest implements http {
  effect request -> github.api.request(
    token: secret("GITHUB_TOKEN"),
    redact: ["authorization", "set-cookie"]
  )
}
```

Adapters must declare their trust boundary:

```intent
adapter ci.shell implements shell {
  trust_boundary external_process
  isolation container(image: "node:22", network: denied)
  logs redact_secrets
}
```

Adapter selection is a deployment concern. Workflow source names the effect, not the vendor-specific tool:

```intent
runtime local {
  bind fs to local.fs
  bind shell to local.shell
  bind http to github.rest
}
```

An adapter may narrow a capability but may not widen it. For example, a hosted adapter may reject `shell.exec` even if the source grants it when the runtime policy disallows shell access.

## Denied Effects

A denied effect is a first-class outcome, not an exception hidden in adapter logs. Denials are typed, auditable, and available to control flow.

```intent
type Denial = {
  code: DenialCode,
  effect: EffectName,
  input_hash: String,
  reason: String,
  policy: String,
  recoverable: Bool
}
```

Denial codes should be stable:

```intent
enum DenialCode {
  CapabilityMissing,
  PathOutsideGrant,
  CommandOutsideGrant,
  DomainOutsideGrant,
  SecretUnavailable,
  ApprovalMissing,
  ApprovalRejected,
  TimeoutExceeded,
  RollbackUnavailable,
  RuntimePolicyDenied
}
```

Workflow code may handle recoverable denials explicitly:

```intent
try {
  shell.exec(command: "npm run lint")
} catch Denied(CommandOutsideGrant) {
  explain "lint command is not declared; stopping instead of expanding permissions"
  stop denied
}
```

Denied effects must not partially execute. If an adapter cannot prove that a denial happened before side effects, it must return `PartialFailure` with the rollback status.

## Approval Gates

Approval gates are typed checkpoints that pause execution before sensitive effects. They are part of the program, not comments or prompt text.

```intent
approval publish_gate {
  before git.push, deploy.release
  require human(role: "maintainer")
  show diff(paths: changed_files)
  show checks(["npm test", "npm run lint"])
  expires after 30m
}
```

An effect can require approval in its signature, capability, or call site. The strictest policy wins.

```intent
capability git.push(remotes: ["origin"], branches: ["main"], approval: required)

git.push(remote: "origin", branch: "main")
  requires approval publish_gate
```

Approval decisions are immutable records:

```intent
type ApprovalRecord = {
  gate: String,
  effect: EffectName,
  normalized_input: Json,
  approver: Principal,
  decision: approved | rejected,
  reason: String,
  created_at: Time,
  expires_at: Time?
}
```

If inputs change after approval, the approval is invalidated unless the gate declares a stable projection:

```intent
approval commit_gate {
  before git.commit
  approve_projection {
    paths
    diff_hash
    message
  }
}
```

## Rollback Contracts

A rollback contract states what the runtime can do if an effect succeeds and later steps fail. Intent distinguishes reversible, compensating, and irreversible effects.

```intent
rollback reversible fs.restore_file(snapshot: before)
rollback compensating git.revert_commit(commit: result.sha)
rollback irreversible require approval release_gate
rollback none
```

Effects that change durable external state should declare one of:

- `reversible`: restores prior state exactly.
- `compensating`: applies a new effect that semantically undoes the prior effect.
- `irreversible`: cannot be undone and therefore needs stronger approval and verification.
- `none`: no rollback is needed because the effect has no durable side effect.

Example:

```intent
effect issue.create(title: String, body: String) -> Issue
  requires issue.create(project: current_project)
  approval optional
  rollback compensating issue.close(id: result.id, reason: "created by rolled back workflow")
```

Rollbacks run in reverse effect order and produce a rollback ledger:

```intent
type RollbackLedger = {
  workflow_id: String,
  failed_step: String,
  entries: List<RollbackEntry>
}

type RollbackEntry = {
  effect_id: String,
  rollback_kind: reversible | compensating | irreversible | none,
  status: skipped | succeeded | failed | unavailable,
  evidence: Json
}
```

The checker requires an explicit `irreversible` marker for effects without rollback. A workflow cannot silently call an irreversible effect.

## Example: Tool Package

```intent
package tools.fs version "0.1" {
  capability read(paths: List<PathPattern>)
  capability write(paths: List<PathPattern>, max_bytes: Int = 1048576)

  effect read_file(path: Path) -> String
    requires fs.read(path)
    denies [PathOutsideGrant, FileMissing, FileTooLarge]
    rollback none

  effect write_file(path: Path, content: String, mode: WriteMode = replace) -> FileWriteResult
    requires fs.write(path)
    denies [PathOutsideGrant, MaxBytesExceeded]
    rollback reversible fs.restore_file(snapshot: result.before)

  effect restore_file(snapshot: FileSnapshot) -> FileWriteResult
    requires fs.write(snapshot.path)
    denies [PathOutsideGrant, SnapshotExpired]
    rollback none
}
```

## Example: Workflow With Effects

```intent
goal "prepare changelog entry" {
  context repo("./")

  capability fs.read(paths: ["CHANGELOG.md", "intent/**"])
  capability fs.write(paths: ["intent/workstreams/*.md"], max_bytes: 100000)
  capability shell.exec(commands: ["npm test"], timeout: 5m)
  capability git.commit(paths: ["intent/workstreams/*.md"])
  capability git.push(remotes: ["origin"], branches: ["main"], approval: required)

  approval publish_gate {
    before git.push
    require human(role: "maintainer")
    show diff(paths: ["intent/workstreams/*.md"])
    show checks(["npm test"])
  }

  plan {
    let changelog = fs.read_file(path: "CHANGELOG.md")
    let entry = summarize(changelog, scope: "intent tools")

    fs.write_file(
      path: "intent/workstreams/tools-and-effects.md",
      content: entry,
      mode: replace
    )

    let tests = shell.exec(command: "npm test")
    verify tests.exit_code == 0

    git.commit(
      message: "Document Intent tools and effects",
      paths: ["intent/workstreams/tools-and-effects.md"]
    )

    git.push(remote: "origin", branch: "main")
      requires approval publish_gate
  }
}
```

## Static Checks

The first checker should enforce:

- Every effect call resolves to an imported signature.
- Every effect call is covered by an in-scope capability.
- Dynamic arguments carry typed constraints before they reach an effect.
- Denied variants named in `catch Denied(...)` exist on the effect signature.
- Approval gates exist for every effect whose signature or capability requires approval.
- Irreversible effects are marked and approved.
- Rollback references only values in scope from the original effect input or result.
- Adapter bindings implement every effect used by the workflow.

## Runtime Requirements

A compliant runtime must:

- Normalize inputs before policy checks.
- Persist an effect ledger before executing each durable effect.
- Redact secrets from logs and denial records.
- Return typed denials without partial execution when policy rejects an effect.
- Record adapter identity, version, normalized input hash, output hash, and rollback status.
- Stop completion until required verification and approval gates pass.
- Execute rollback contracts when a failed workflow requests rollback.

## Open Questions

- Should capability grants be inferred from effect calls and then approved as a manifest?
- Should adapters be allowed to expose richer native types than the standard effect package?
- How long should file snapshots and rollback artifacts be retained?
- Can approval gates be delegated to policy engines such as OPA without losing type safety?
- Should denied effects be resumable after capability edits, or should the workflow restart from the last checkpoint?
