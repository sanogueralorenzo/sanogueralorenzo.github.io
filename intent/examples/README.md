# Intent Examples

These examples make Intent concrete as an agent-first typed workflow language. Each
workflow declares typed inputs, bounded context, allowed capabilities, resumable
steps, visible effects, verification gates, and human approval points.

## Code Change

Use this workflow when an agent must make a small repository change with tests and
traceable file writes.

```intent
workflow CodeChange {
  input ticket: TicketRef
  input repo: GitRepo
  input request: ChangeRequest

  context {
    source repository(repo, scope: request.allowed_paths)
    source ticket_system(ticket)
  }

  capabilities {
    file.read(paths: request.allowed_paths)
    file.write(paths: request.allowed_paths)
    shell.exec(commands: ["npm test", "npm run typecheck"])
    git.diff()
  }

  invariants {
    no_secret_writes()
    no_unrelated_files()
    no_untyped_public_api()
  }

  step Inspect -> FindingSet {
    read ticket.acceptance_criteria
    read repository.files
    emit FindingSet(summary, touched_symbols, risk)
  }

  step Patch(input findings: FindingSet) -> PatchSet {
    effect FileWrite(paths: request.allowed_paths)
    emit PatchSet(files, rationale)
  }

  step Verify(input patch: PatchSet) -> VerificationReport {
    effect ShellExec(command: "npm run typecheck")
    effect ShellExec(command: "npm test")
    require all_commands_passed()
    emit VerificationReport(commands, failures, coverage_notes)
  }

  step Review(input report: VerificationReport) -> Completion {
    require git.diff_contains_only(request.allowed_paths)
    emit Completion(summary, changed_files, verification: report.commands)
  }
}
```

The important part is that the agent cannot write outside the requested paths, and
completion is blocked until the typed verification report proves the allowed checks
passed.

## Research Synthesis

Use this workflow when an agent must combine source material into a cited answer
without turning uncertain claims into facts.

```intent
workflow ResearchSynthesis {
  input question: ResearchQuestion
  input source_policy: SourcePolicy

  context {
    source web(domains: source_policy.allowed_domains)
    source documents(paths: source_policy.local_paths)
  }

  capabilities {
    web.read(domains: source_policy.allowed_domains)
    file.read(paths: source_policy.local_paths)
  }

  invariants {
    cite_external_claims()
    separate_fact_from_inference()
    respect_source_word_limits()
  }

  step Collect -> SourceSet {
    require source_count(min: 3)
    emit SourceSet(items: List<SourceRef>)
  }

  step Extract(input sources: SourceSet) -> EvidenceTable {
    emit EvidenceTable(
      claims: List<Claim>,
      citations: Map<ClaimId, SourceRef>,
      conflicts: List<Conflict>
    )
  }

  step Synthesize(input evidence: EvidenceTable) -> DraftAnswer {
    require every_claim_has_citation(evidence.claims)
    effect None
    emit DraftAnswer(sections, confidence, open_questions)
  }

  step Verify(input draft: DraftAnswer) -> ResearchReport {
    require no_uncited_external_claims(draft)
    require uncertainty_marked(draft)
    emit ResearchReport(answer: draft, sources_used, unresolved_conflicts)
  }
}
```

The workflow treats citations, conflicts, and confidence as typed outputs instead
of prose conventions, so the final answer keeps provenance attached to each claim.

## Incident Response

Use this workflow when an agent must triage a production incident while keeping
destructive operations gated.

```intent
workflow IncidentResponse {
  input incident: IncidentRef
  input service: ServiceRef
  input severity: Severity

  context {
    source pager(incident)
    source logs(service, window: 2h)
    source metrics(service, window: 2h)
    source runbook(service)
  }

  capabilities {
    logs.read(service)
    metrics.read(service)
    ticket.update(incident)
    chat.post(channel: incident.channel)
    deploy.rollback(service) requires HumanApproval
  }

  invariants {
    preserve_customer_data()
    timestamp_status_updates()
    require_human_for_destructive_effects()
  }

  step Assess -> IncidentState {
    read logs.errors
    read metrics.slo
    read runbook.known_failure_modes
    emit IncidentState(impact, suspected_cause, confidence)
  }

  step Stabilize(input state: IncidentState) -> MitigationPlan {
    if state.impact == "customer_facing" {
      effect ChatPost(message: status_update(state))
      effect TicketUpdate(status: "investigating")
    }
    emit MitigationPlan(actions, rollback_candidate, risk)
  }

  step Mitigate(input plan: MitigationPlan) -> MitigationResult {
    if plan.rollback_candidate != null {
      require HumanApproval(reason: "rollback production service")
      effect DeployRollback(service)
    }
    effect TicketUpdate(status: "mitigating")
    emit MitigationResult(actions_taken, current_metrics)
  }

  step CloseOrEscalate(input result: MitigationResult) -> IncidentOutcome {
    if result.current_metrics.slo_restored {
      effect TicketUpdate(status: "resolved")
      emit IncidentOutcome(state: "resolved", followups)
    } else {
      effect ChatPost(message: escalation_request(result))
      emit IncidentOutcome(state: "escalated", blockers)
    }
  }
}
```

This makes read-only diagnosis available to the agent, while rollback remains a
typed effect that cannot run without explicit human approval.

## Deployment Approval

Use this workflow when an agent must prepare a release decision from checks,
change summaries, and risk signals.

```intent
workflow DeploymentApproval {
  input release: ReleaseCandidate
  input environment: Environment

  context {
    source git.release_diff(release)
    source ci.pipeline(release)
    source change_log(release)
    source deployment_policy(environment)
  }

  capabilities {
    git.read()
    ci.read()
    deploy.plan(environment)
    deploy.execute(environment) requires HumanApproval
    ticket.update(release.approval_ticket)
  }

  invariants {
    no_deploy_with_failing_required_checks()
    no_unreviewed_database_migration()
    require_named_approver()
  }

  step Summarize -> ReleaseSummary {
    emit ReleaseSummary(changes, migrations, flags, affected_services)
  }

  step CheckReadiness(input summary: ReleaseSummary) -> ReadinessReport {
    require ci.required_checks_passed(release)
    require policy.satisfied(environment, summary)
    emit ReadinessReport(risk, blockers, required_approvers)
  }

  step RequestApproval(input report: ReadinessReport) -> ApprovalDecision {
    effect TicketUpdate(status: "approval_requested", body: report)
    require HumanApproval(
      approver: report.required_approvers.primary,
      reason: "deploy " + release.version + " to " + environment.name
    )
    emit ApprovalDecision(approved_by, approved_at, conditions)
  }

  step Deploy(input decision: ApprovalDecision) -> DeploymentResult {
    require decision.approved_by != null
    effect DeployPlan(environment)
    effect DeployExecute(environment)
    effect TicketUpdate(status: "deployed")
    emit DeploymentResult(version: release.version, environment, audit_log)
  }
}
```

The deployment action is separated from readiness analysis, so an agent can gather
evidence and request approval without being allowed to release until the typed
approval decision exists.
