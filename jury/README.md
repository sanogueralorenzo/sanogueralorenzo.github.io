# Jury

Jury is a typed adversarial review layer for AI agents.

It treats every important agent outcome as a claim that must survive challenge before it is accepted. A proposing agent can say that a task is complete, a change is safe, or a deployment is ready, but Jury requires critics, verifiers, and policy checks to test that claim against evidence.

The goal is simple: AI systems should not only produce answers. They should prove that their answers can withstand structured objection.

## Core Idea

Most agent systems have a weak completion boundary:

- The agent says it is done.
- A test command passes.
- A reviewer skims the diff.
- A human approves without seeing the full reasoning path.
- A risky action proceeds because no one asked the right objection.

Jury turns completion into a verdict. Before a high-impact action proceeds, the system gathers claims, objections, evidence, reproductions, unresolved risks, and explicit waivers into one auditable record.

## How It Fits With Intent And Precedent

Jury is designed to work beside the other agent-first systems in this repository:

- `Intent` defines the goal, permissions, invariants, verification requirements, and approval boundaries.
- `Precedent` injects relevant lessons from prior agent runs so repeated mistakes are challenged earlier.
- `Jury` decides whether the current claim has survived enough adversarial review to be accepted.

Together, they form a loop:

1. Intent states what the agent is allowed and required to do.
2. Precedent reminds the agent what this repository has already learned.
3. Jury challenges the final claim before the system treats it as true.

## Review Roles

Jury models review as explicit roles instead of vague agreement:

- `proposer`: makes a claim, such as "the checkout fix is complete."
- `critic`: searches for false assumptions, missing cases, risky edits, or weak evidence.
- `verifier`: reruns commands, checks artifacts, validates citations, or reproduces behavior.
- `policy`: evaluates security, privacy, compliance, permissions, and approval requirements.
- `judge`: resolves the review record into an accept, reject, retry, or human-decision verdict.

These roles can be separate agents, deterministic tools, human reviewers, or a mix of all three.

## Verdict Artifact

The central output is a durable verdict:

```json
{
  "schema_version": "jury.verdict.v1",
  "claim": "checkout fix is ready to merge",
  "decision": "accept",
  "proposer": "agent:codex",
  "review": {
    "objections": [
      {
        "id": "obj_missing_regression_test",
        "status": "resolved",
        "raised_by": "critic:test",
        "summary": "The original patch did not cover the failed coupon path.",
        "resolution": "Added a regression test for expired coupon checkout."
      }
    ],
    "evidence": [
      {
        "type": "command",
        "value": "npm test",
        "exit_code": 0
      },
      {
        "type": "diff",
        "value": "src/checkout/applyCoupon.ts"
      }
    ],
    "waivers": []
  },
  "accepted_at": "2026-05-23T00:00:00Z"
}
```

A verdict is not a transcript. It is the smallest review record needed to understand what was claimed, what was challenged, what evidence was checked, and why the outcome was accepted or rejected.

## Verdict States

- `accept`: the claim satisfied required review and verification.
- `reject`: the claim failed review and should not proceed.
- `retry`: the claim may become acceptable after specific fixes.
- `human_decision`: the system found a judgment call that must be resolved by a person.

Jury should make unresolved risk visible instead of hiding it behind confident language.

## Design Principles

1. Completion is a claim.
2. Claims need evidence.
3. Evidence must be reproducible when possible.
4. Objections are first-class review artifacts.
5. Silence is not approval.
6. Waivers must be explicit and attributable.
7. High-impact actions require stronger review.
8. The judge must explain the verdict.
9. Review should be scoped to the actual risk.
10. The verdict should be durable enough for future agents to learn from.

## Example: Code Change Gate

```jury
claim "checkout fix is ready" {
  proposer agent("codex")
  context repo("./")
  evidence command("npm test")
  evidence diff("src/checkout")

  require critic("tests")
  require critic("security")
  require verifier("reproduce_failure")

  accept when {
    no_open_objections severity >= "medium"
    required_evidence passed
    no_unapproved_policy_violations
  }
}
```

## Example: Deployment Gate

```jury
claim "deploy billing service" {
  proposer agent("release")
  context intent_goal("deploy billing hotfix")
  context precedent(scope: "service:billing")

  require verifier("smoke_tests")
  require verifier("rollback_plan")
  require policy("production_approval")
  require human_approval from "oncall"

  reject when {
    rollback_plan missing
    open_objection severity >= "high"
  }
}
```

## MVP

The smallest useful version would include:

1. A `jury review` command that accepts a claim, evidence files, command results, and policy requirements.
2. A structured objection format with severity, scope, evidence, and resolution status.
3. A verifier that can rerun declared commands and attach results.
4. A judge that emits `verdict.json`.
5. A merge or deploy gate that refuses to proceed without an acceptable verdict.

The first prototype should focus on code-change review because it has concrete evidence: diffs, tests, typechecks, logs, screenshots, and review comments.

## Open Questions

- How many independent reviewers are needed before a verdict is trustworthy?
- When should a critic be another model, a deterministic tool, or a human?
- How should Jury prevent review loops where agents keep inventing low-value objections?
- Can verdicts become training data for better future critics?
- What is the right threshold for requiring human approval?
- How should Jury represent disagreement when two reviewers make defensible but incompatible claims?

## Long-Term Vision

Jury turns AI output from assertion into adjudication.

Instead of asking whether an agent sounds confident, a system can ask:

- What exactly is being claimed?
- Who challenged it?
- What evidence was checked?
- What risks remain?
- Who accepted those risks?
- Can another agent or human audit the verdict later?

If Intent is the contract and Precedent is the memory, Jury is the accountable decision boundary.
