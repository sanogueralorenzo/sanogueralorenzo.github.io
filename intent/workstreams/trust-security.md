# Intent Trust And Security Policy

Intent needs a trust model that is concrete enough for static checks, runtime
enforcement, audit review, and human intervention. This note defines the first
policy surface for an agent-first typed workflow language.

The security model treats every meaningful action as a typed effect performed by
a principal inside a trust zone under explicit capability scopes. Policy checks
must happen before effects run, while effects run, and before a goal is marked
complete.

## Goals

- Make trust boundaries explicit in the program.
- Bind every side effect to a principal, capability, and audit record.
- Keep secrets scoped, non-copyable by default, and absent from logs.
- Make human approval a typed gate with durable evidence.
- Fail closed when policy cannot be evaluated.
- Give operators enough provenance to understand what happened and why.

## Non-Goals

- Intent does not replace host sandboxing, operating-system permissions, cloud
  IAM, or network controls.
- Intent does not assume all runtimes share one identity provider.
- Intent does not make unsafe effects safe; it only makes them explicit,
  checkable, and auditable.

## Trust Zones

A trust zone is a named execution boundary with declared data and effect rules.
Every context source, tool adapter, memory store, secret, and effect target must
belong to exactly one zone.

```intent
trust_zone local_repo {
  boundary filesystem(path: "./")
  data_classification internal
  network none
}

trust_zone public_web {
  boundary web(domains: ["example.com"])
  data_classification public
  network outbound_https
}

trust_zone production {
  boundary cloud(account: "prod")
  data_classification restricted
  network controlled
  requires human_approval
}
```

Required zone fields:

- `boundary`: the concrete resource boundary, such as a path, domain, account,
  database, queue, ticket project, or chat workspace.
- `data_classification`: `public`, `internal`, `confidential`, or `restricted`.
- `network`: `none`, `outbound_https`, `controlled`, or a runtime-defined
  profile.
- `requires`: optional gates that apply to all effects in the zone.

Default rule: if a resource is not assigned to a zone, the runtime must reject
access to it.

## Principals

A principal is the actor accountable for an effect. Intent separates the person
requesting the work, the agent interpreting the workflow, and the runtime or
tool identity that performs effects.

```intent
principal requester {
  kind human
  subject "user:mario"
}

principal agent {
  kind agent
  model "runtime-selected"
  delegated_by requester
}

principal github_token {
  kind service_account
  subject "github-actions:repo-writer"
  delegated_by requester
}
```

Principal kinds:

- `human`: a person who can request work, approve gates, or review audit logs.
- `agent`: a reasoning process that plans and proposes effects.
- `service_account`: a non-human identity used by a tool adapter.
- `system`: a runtime component such as a scheduler, verifier, or policy engine.

Every effect must record both `decided_by` and `executed_by`. For example, an
agent may decide to call a shell command, while the local runtime identity
executes it.

## Capability Scopes

Capabilities are typed grants. They must name the allowed action, target zone,
target selector, and constraints. Broad capabilities are invalid unless the
runtime marks them as interactive development mode and still audits them.

```intent
capability file.read {
  zone local_repo
  paths ["intent/**"]
}

capability file.write {
  zone local_repo
  paths ["intent/workstreams/trust-security.md"]
  max_bytes 20000
}

capability shell.exec {
  zone local_repo
  commands ["npm test", "npm run lint"]
  timeout 5m
  network none
}

capability git.push {
  zone local_repo
  branches ["main"]
  requires human_approval("publish")
}
```

Capability fields:

- `action`: the typed effect family, such as `file.read`, `file.write`,
  `shell.exec`, `http.get`, `ticket.update`, `memory.write`, `secret.read`,
  `git.commit`, `git.push`, or `deploy.apply`.
- `zone`: the trust zone where the target lives.
- `selector`: the concrete resource subset, such as paths, commands, domains,
  tables, queues, projects, branches, or environment names.
- `constraints`: bounded limits such as timeouts, byte limits, schemas, allowed
  headers, retry budgets, rate limits, and network profiles.
- `requires`: approval, verification, or policy gates that must pass before use.

Default rule: a step can only produce an effect if a matching capability exists
and all constraints are satisfied.

## Secrets

Secrets are typed references, not strings. They can be passed only to effect
adapters that declare secret inputs, and they must not be copied into memory,
logs, prompts, generated files, or human-readable output.

```intent
secret github_push_token {
  zone local_repo
  provider keychain("github-push")
  allowed_effects [git.push]
  reveal never
  ttl 10m
}
```

Secret policy:

- `reveal never`: the agent receives an opaque handle only.
- `reveal masked`: humans may see a redacted fingerprint.
- `reveal explicit`: a human can reveal the value only through a separate
  approval gate; the event must be audited.
- Secret handles are non-serializable unless the target checkpoint store is
  approved for secret references.
- Secret-derived values inherit the same restrictions as the original secret.
- Failed secret access must not disclose whether the secret exists unless the
  caller has `secret.describe`.

## Human Approval

Human approval is a typed gate, not a comment in a plan. An approval gate names
the approver set, the effect being approved, the evidence shown, and the maximum
time the approval remains valid.

```intent
approval publish {
  approvers [requester]
  applies_to [git.push, deploy.apply]
  evidence [
    diff_summary,
    verification_results,
    policy_decision,
    rollback_plan
  ]
  expires_after 15m
  single_use true
}
```

Approval requirements:

- The approver must be a principal authorized for the target zone.
- The approval record must bind to the exact effect payload or a stable digest.
- Material changes after approval invalidate the gate.
- Denial is final for that effect payload unless a new plan revision is created.
- Approval prompts must include known risks, verification state, and rollback
  availability.

## Audit Logs

Every policy decision and effect must emit an append-only audit event. Audit
events are part of Intent provenance and must be queryable by goal, step,
principal, zone, capability, and effect id.

```intent
audit_event EffectRequested {
  goal_id GoalId
  step_id StepId
  effect_id EffectId
  decided_by PrincipalId
  requested_capability CapabilityId
  target_zone TrustZoneId
  payload_digest Sha256
  timestamp Instant
}
```

Minimum event types:

- `PolicyChecked`: allow, deny, or require approval.
- `ApprovalRequested`: evidence and approver set.
- `ApprovalGranted`: approver, scope, expiry, and payload digest.
- `ApprovalDenied`: approver and denial reason.
- `EffectRequested`: normalized effect payload and capability request.
- `EffectStarted`: executor identity and runtime adapter.
- `EffectCompleted`: result digest and produced artifacts.
- `EffectFailed`: failure class, retryability, and partial-effect marker.
- `SecretAccessed`: secret handle id, target adapter, and non-revealing result.
- `VerificationCompleted`: checks run and pass/fail result.

Audit logs must not contain raw secrets, private prompt fragments beyond the
declared evidence set, or unbounded tool output. Large payloads should be stored
as content-addressed artifacts with classification metadata.

## Policy Checks

Intent uses two layers of policy checks: static checks before execution and
runtime checks before each effect.

Static checks:

- Every context, capability, secret, memory store, and effect target belongs to a
  trust zone.
- Every step declares the effects it may produce.
- Every declared effect has a matching capability.
- Cross-zone data flow is allowed by classification and zone rules.
- Secret handles are only passed to allowed effect adapters.
- Approval gates exist for effects whose zones or capabilities require them.
- Verification and rollback requirements are declared for irreversible effects.

Runtime checks:

- The active principal is allowed to use the capability.
- The effect payload matches the capability selector and constraints.
- Required approvals are current, single-use status is valid, and payload digests
  match.
- Secret handles are valid, unexpired, and used only by approved adapters.
- Retry attempts remain within budget.
- Output classifications do not exceed the destination zone.
- The audit sink is available before irreversible effects run.

Policy result type:

```intent
type PolicyDecision =
  | Allow { obligations: Obligation[] }
  | RequireApproval { approval: ApprovalId, evidence: Evidence[] }
  | Deny { reason: PolicyReason, retryable: Bool }
```

Obligations are extra runtime duties attached to an allow decision, such as
masking output, recording a checksum, scheduling verification, or deleting a
temporary artifact.

## Failure Modes

Security failures must be explicit and typed so a workflow can stop, request
human input, retry safely, or run compensation.

```intent
type SecurityFailure =
  | MissingCapability
  | ScopeViolation
  | UnknownTrustZone
  | PrincipalNotAuthorized
  | ApprovalRequired
  | ApprovalExpired
  | ApprovalPayloadMismatch
  | SecretUnavailable
  | SecretPolicyViolation
  | AuditUnavailable
  | PolicyEngineUnavailable
  | CrossZoneFlowDenied
  | VerificationRequired
```

Failure handling rules:

- `MissingCapability`, `ScopeViolation`, `PrincipalNotAuthorized`,
  `SecretPolicyViolation`, and `CrossZoneFlowDenied` fail closed.
- `ApprovalRequired` pauses the workflow until a valid approval is recorded.
- `ApprovalExpired` and `ApprovalPayloadMismatch` require a new approval.
- `SecretUnavailable` may retry only if the secret provider marks the error as
  transient.
- `AuditUnavailable` blocks irreversible effects and may allow read-only effects
  if local buffering is configured.
- `PolicyEngineUnavailable` blocks all effects except policy-health checks.
- `VerificationRequired` blocks goal completion, even if the effect succeeded.

Partial effects must be represented as first-class state. A failed deploy, file
write, ticket update, or external call cannot be hidden inside an exception; the
runtime must record what may have changed and whether compensation is available.

## Cross-Zone Data Flow

Data can move from one zone to another only through an explicit flow rule.

```intent
flow local_repo -> public_web {
  allows [http.post]
  max_classification public
  transform redact_secrets
  requires policy_check("egress")
}
```

Default flow rules:

- `public` data may flow to any zone.
- `internal` data may flow only to zones with equal or stronger classification.
- `confidential` and `restricted` data require an explicit flow declaration.
- Secret-bearing data cannot cross zones unless transformed into a non-secret
  derived value approved by policy.
- Human approval can authorize an effect, but it does not bypass classification
  or secret rules unless the policy explicitly allows an emergency override.

## Typed Effect Envelope

All effects share a common envelope so policy and audit code can operate before
adapter-specific execution.

```intent
effect FileWrite {
  id EffectId
  decided_by PrincipalId
  executed_by PrincipalId
  capability CapabilityId
  zone TrustZoneId
  payload FileWritePayload
  payload_digest Sha256
  approval ApprovalId?
  rollback RollbackPlan?
}
```

The adapter-specific payload is validated after the envelope passes policy.
Adapters must return a typed result with output classification, artifact digests,
and partial-effect status.

## Completion Gate

A goal cannot complete until the trust and security policy can prove:

- All effects were allowed by policy.
- Required approvals were granted and bound to the executed payloads.
- Required audit events were written.
- Secret handles were not leaked into outputs, memory, prompts, or logs.
- Cross-zone flows matched declared rules.
- Required verification completed successfully.
- Partial effects are either resolved, compensated, or explicitly accepted by an
  authorized human.

## Open Questions

- Should Intent define a standard policy language or compile to host engines
  such as OPA, Cedar, or cloud IAM conditions?
- How should policy handle collaborative goals with multiple human requesters?
- What is the smallest useful classification model for local-first workflows?
- Should emergency override be a core language feature or a runtime extension?
- How much prompt and model trace data should audit logs retain by default?
