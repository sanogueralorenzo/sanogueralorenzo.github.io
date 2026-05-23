# Intent Examples

These examples are executable v0 Intent programs. Each file is expected to
parse, check, and emit an executable graph through the Phase 2 static model.

## Run

```shell
node intent/bin/intent.mjs parse intent/examples/code_change.intent
node intent/bin/intent.mjs check intent/examples/code_change.intent
node intent/bin/intent.mjs graph intent/examples/code_change.intent
```

The full example set is covered by `node --test intent/test/*.test.mjs`.

## Files

- `code_change.intent`: a typed repository change with bounded file writes,
  shell verification, checkpoints, memory retention, and file-write
  invariants.
- `research_synthesis.intent`: a cited research workflow with web and document
  sources, read-only capabilities, retained evidence, and citation-focused
  verification.
- `incident_response.intent`: an incident triage workflow with ticket updates,
  runbook context, approval-gated mitigation, and production-deploy denial.
- `deployment_approval.intent`: a release approval workflow with retained
  approval evidence, ticket updates, approval-gated deployment, and deployment
  invariants.

These examples intentionally stay inside the v0 grammar. Richer syntax such as
conditionals, adapter-specific records, policy expressions, and nested calls is
reserved for later schema versions.
