# Intent Fixtures

These fixtures exercise the Phase 2 static model parser and checker.

## Valid

- `valid_code_change.intent`: code-change goal with declared step output types, repository context, file and shell capabilities, allowed `FileWrite` and `ShellExec` calls, verification, and invariants.
- `valid_checkpoint_graph.intent`: code-change goal with step body `checkpoint ...` lines, normal file and shell capabilities, checkpoint memory retention, verification, and invariants.
- `valid_context_trust_graph.intent`: context graph goal with repository, web, and document sources, read-only file and web capabilities, memory retention, plan steps, verification, and trust invariants.
- `valid_dependency_graph.intent`: named goal input feeding the first step, followed by prior step outputs feeding later steps for graph dependency coverage.
- `valid_research.intent`: research goal with declared source, claim, and report types, web and local document context, read-only capabilities, plan steps, citation verification, and invariants.
- `valid_trust_flow_shell_literal.intent`: trust-flow goal where `ShellExec` uses a literal command declared by shell capability.
- `valid_web_read_wildcard.intent`: web-read goal where `WebRead` targets a subdomain covered by a wildcard web domain grant.
- `valid_git_push_branch.intent`: git goal where `GitPush` targets a branch covered by a normalized git push branch grant.
- `valid_deploy_target.intent`: deploy goal where `Deploy` targets an environment covered by a deploy target grant, with memory retention, verification, and invariants.
- `valid_secret_read.intent`: secret-read goal where `SecretRead` targets a secret name covered by a secret read grant, with memory retention, verification, and invariants.
- `valid_ticket_update.intent`: ticket-update goal where `TicketUpdate` targets a ticket id covered by a ticket update grant, with memory retention, verification, and invariants.
- `valid_step_requirements.intent`: code-change goal with step-local `require ...` guards before effects, normal file and shell capabilities, memory retention, verification, and invariants.
- `valid_invariant_guard_graph.intent`: code-change goal with invariant rules intended to guard multiple graph targets, including file and shell effects plus step checkpoints, with normal capabilities, checkpoint memory retention, plan steps, and verification.
- `valid_step_approval_graph.intent`: code-change goal with step body `approval ...` lines before sensitive file-write and git-push effects, normal file, shell, and git capabilities, approval memory retention, verification, and invariants.
- `valid_step_policy_graph.intent`: code-change goal with step body `timeout ...` and `retry ...` lines before file and shell effects, normal file and shell capabilities, memory retention, verification, and invariants.

## Invalid

- `invalid_missing_verification.intent`: declares mutating effects but omits the required verification gate.
- `invalid_undeclared_effect.intent`: uses a git push step without declaring the matching capability.
- `invalid_git_push_branch_mismatch.intent`: declares git push access for `main` but calls `GitPush(branch: "release")`.
- `invalid_deploy_target_outside_capability.intent`: declares deploy access for `staging` but calls `Deploy` for `production`.
- `invalid_approval_required_missing.intent`: declares git push access for `main` with approval required but calls `GitPush(branch: "main")` without a step approval gate.
- `invalid_file_write_outside_capability.intent`: calls `FileWrite` for a path outside the declared write grant.
- `invalid_shell_exec_outside_capability.intent`: calls `ShellExec` with a command outside the declared shell grant.
- `invalid_web_read_outside_capability.intent`: calls `WebRead` for a URL outside the declared web domain grant.
- `invalid_secret_read_outside_capability.intent`: declares secret read access for `GITHUB_TOKEN` but calls `SecretRead` for `AWS_TOKEN`.
- `invalid_ticket_update_outside_capability.intent`: declares ticket update access for `CODE-123` but calls `TicketUpdate` for `CODE-999`.
- `invalid_context_source_outside_capability.intent`: declares a web context source outside the declared web read grant.
- `invalid_verify_shell_without_capability.intent`: requires `shell("npm run lint")` in verification without declaring the matching shell run grant.
- `invalid_verify_impure_file_write.intent`: declares normal file and shell capabilities but calls `FileWrite(path: "./src/app.ts")` from `verify`, which should be rejected because verification must stay side-effect free.
- `invalid_memory_without_retention.intent`: declares a memory block without any `retain ... until ...` retention rule.
- `invalid_unresolved_type.intent`: uses a step output type that is not declared.
- `invalid_unresolved_step_input.intent`: uses a declared step input type before any goal input or earlier step produces it.
- `invalid_duplicate_step_name.intent`: declares the same step name twice in one plan.
- `invalid_trust_flow_untrusted_shell_input.intent`: feeds a value produced from web context into `ShellExec(command: input)`.
