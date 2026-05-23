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
- `valid_git_commit_message.intent`: git goal where `GitCommit` uses a message covered by a git commit message grant.
- `valid_deploy_target.intent`: deploy goal where `Deploy` targets an environment covered by a deploy target grant, with memory retention, verification, and `deny production_deploy` invariants.
- `valid_secret_read.intent`: secret-read goal where `SecretRead` targets a secret name covered by a secret read grant, with memory retention, verification, and invariants.
- `valid_ticket_update.intent`: ticket-update goal where `TicketUpdate` targets a ticket id covered by a ticket update grant, with memory retention, verification, and invariants.
- `valid_step_requirements.intent`: code-change goal with step-local `require ...` guards before effects, normal file and shell capabilities, memory retention, verification, and invariants.
- `valid_invariant_guard_graph.intent`: code-change goal with invariant rules intended to guard multiple graph targets, including file and shell effects plus step checkpoints, with normal capabilities, checkpoint memory retention, plan steps, and verification.
- `valid_imports.intent`: import-focused parser fixture that preserves package and symbol import declarations with source spans while keeping imported names out of checker scope.
- `valid_memory_flow_graph.intent`: memory provenance goal with step-local memory write, read, and citation access emitted as graph edges.
- `valid_step_approval_graph.intent`: code-change goal with step body `approval ...` lines before sensitive file-write and git-push effects, normal file, shell, and git capabilities, approval memory retention, verification, and invariants.
- `valid_step_policy_graph.intent`: code-change goal with step body `timeout ...` and `retry ...` lines before file and shell effects, normal file and shell capabilities, memory retention, verification, and invariants.

## Invalid

- `invalid_goal_missing.intent`: declares package, import, and type declarations but no goal, which should fail `INTENT_GOAL_MISSING` at the source span.
- `invalid_missing_package.intent`: starts with a type declaration instead of the required package declaration, which should fail `INTENT_PARSE_ERROR`.
- `invalid_duplicate_package.intent`: declares two package declarations, which should fail `INTENT_PARSE_ERROR`.
- `invalid_import_after_type.intent`: declares an import after a type declaration, which should fail `INTENT_PARSE_ERROR`.
- `invalid_missing_verification.intent`: declares mutating effects but omits the required verification gate.
- `invalid_undeclared_effect.intent`: uses a git push step without declaring the matching capability.
- `invalid_git_push_branch_mismatch.intent`: declares git push access for `main` but calls `GitPush(branch: "release")`.
- `invalid_git_commit_message_mismatch.intent`: declares git commit access for `ship fix` but calls `GitCommit(message: "release fix")`.
- `invalid_deploy_target_outside_capability.intent`: declares deploy access for `staging` but calls `Deploy` for `production`, which should fail `INTENT_CAPABILITY_DENIED` at the target argument span.
- `invalid_invariant_production_deploy.intent`: declares deploy access for `production` but denies `production_deploy`, which should fail `INTENT_INVARIANT_VIOLATION` at the invariant line span.
- `invalid_invariant_secret_write.intent`: declares file write access for `./.env` but denies `secret_write`, which should fail `INTENT_INVARIANT_VIOLATION` at the invariant line span.
- `invalid_invariant_unrelated_file_write.intent`: declares file write access outside the `repo("./src")` context root while denying `unrelated_file_write`, which should fail `INTENT_INVARIANT_VIOLATION` at the invariant line span.
- `invalid_approval_required_missing.intent`: declares git push access for `main` with approval required but calls `GitPush(branch: "main")` without a step approval gate.
- `invalid_file_write_outside_capability.intent`: calls `FileWrite` for a path outside the declared write grant.
- `invalid_file_write_absolute_path.intent`: calls `FileWrite` with an absolute path, which should fail `INTENT_CAPABILITY_DENIED` because file paths must stay relative to the package root.
- `invalid_shell_exec_outside_capability.intent`: calls `ShellExec` with a command outside the declared shell grant.
- `invalid_web_read_outside_capability.intent`: calls `WebRead` for a URL outside the declared web domain grant.
- `invalid_secret_read_outside_capability.intent`: declares secret read access for `GITHUB_TOKEN` but calls `SecretRead` for `AWS_TOKEN`.
- `invalid_ticket_update_outside_capability.intent`: declares ticket update access for `CODE-123` but calls `TicketUpdate` for `CODE-999`.
- `invalid_context_source_outside_capability.intent`: declares a web context source outside the declared web read grant.
- `invalid_verify_shell_without_capability.intent`: requires `shell("npm run lint")` in verification without declaring the matching shell run grant.
- `invalid_verify_impure_file_write.intent`: declares normal file and shell capabilities but calls `FileWrite(path: "./src/app.ts")` from `verify`, which should fail `INTENT_VERIFY_IMPURE` at the impure `FileWrite(...)` call span because verification must stay side-effect free.
- `invalid_memory_without_retention.intent`: declares a memory block without any `retain ... until ...` retention rule.
- `invalid_memory_retention_unknown_until.intent`: declares a parsed memory retention rule with unsupported lifecycle target `forever`, which should fail `INTENT_MEMORY_RETENTION_INVALID`.
- `invalid_memory_access_undeclared.intent`: references undeclared memory from a step-local memory access statement, which should fail `INTENT_MEMORY_UNDECLARED`.
- `invalid_memory_key_undeclared.intent`: references a memory key that is not declared by the memory block's retained subjects or explicit keys, which should fail `INTENT_MEMORY_KEY_UNDECLARED`.
- `invalid_checkpoint_empty.intent`: declares an empty step checkpoint label, which should fail `INTENT_CHECKPOINT_INVALID` once checkpoint validation is enforced.
- `invalid_approval_empty.intent`: declares an empty step approval label, which should fail `INTENT_APPROVAL_INVALID` once approval validation is enforced.
- `invalid_step_policy_bad_timeout.intent`: declares a step timeout policy with unsupported duration `soon`, which should fail `INTENT_POLICY_INVALID` once policy validation is enforced.
- `invalid_duplicate_type_name.intent`: declares the same top-level type name twice.
- `invalid_duplicate_goal_name.intent`: declares the same top-level goal name twice.
- `invalid_duplicate_goal_input.intent`: declares the same goal input name twice and should fail `INTENT_NAME_DUPLICATE` at the duplicate parameter span.
- `invalid_duplicate_step_input.intent`: declares the same step input name twice and should fail `INTENT_NAME_DUPLICATE` at the duplicate parameter span.
- `invalid_unsupported_goal_statement.intent`: declares an otherwise valid-looking goal with unsupported raw goal statement `delegate reviewer`, which should fail `INTENT_UNSUPPORTED_SYNTAX` at that statement span.
- `invalid_unresolved_type.intent`: uses a step output type that is not declared.
- `invalid_goal_output_type_mismatch.intent`: declares goal output `ExpectedReport` but the final plan step outputs `DraftPatch`, which should fail `INTENT_TYPE_MISMATCH` at the final step output type span.
- `invalid_unresolved_step_input.intent`: uses a declared step input type before any goal input or earlier step produces it.
- `invalid_duplicate_step_name.intent`: declares the same step name twice in one plan.
- `invalid_trust_flow_untrusted_shell_input.intent`: feeds a value produced from web context into `ShellExec(command: input)`.
- `invalid_trust_flow_untrusted_effect_sinks.intent`: feeds a value produced from web context into constrained effect sink arguments such as file write paths, secret names, ticket ids, deploy targets, git branches, and git commit messages.
