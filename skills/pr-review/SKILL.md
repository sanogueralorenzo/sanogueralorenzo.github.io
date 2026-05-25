---
name: pr-review
description: Multi-turn pull request review workflow. Use when reviewing a GitHub PR with local Codex tooling, gh, and acli; runs a general review first, then focused simplification, naming, and documentation passes.
---

# PR Review

Review pull requests in four focused turns. Assume `gh`, `acli`, `codex`, and `codex-core` are installed and authenticated before starting. Do not install tools or change repository code during review.

## Operating Rules

- State assumptions before running the review.
- Ask only when the PR target, publish mode, or repository context is ambiguous.
- Review the diff and surrounding code, not only the patch.
- Prefer concrete bugs, regressions, missing tests, and confusing code over style opinions.
- Keep findings concise and actionable.
- Do not invent risk. If a concern is speculative, label it as speculative or omit it.
- Post findings after each pass when the workflow is configured to publish incrementally.

## Workflow

1. General review
   - Check correctness, regressions, data flow, async behavior, error states, security-sensitive paths, and test gaps.
   - Prioritize issues that could break user-visible behavior or production operation.
   - Verify each finding against the diff or nearby code before reporting it.

2. Simplification pass
   - Look for code that solves the requested change with unnecessary machinery.
   - Flag speculative configuration, premature abstraction, duplicate logic, deep nesting, and long functions.
   - Prefer smaller, explicit code when it preserves behavior.
   - Do not request broad refactors outside the PR scope.

3. Naming pass
   - Check whether names explain intent at the call site.
   - Flag vague, overloaded, misleading, or inconsistent names.
   - Prefer domain names over implementation-detail names.
   - Avoid naming comments when the existing name is already clear enough.

4. Documentation pass
   - Check user-facing docs, README changes, command examples, and behavior notes when the PR changes visible behavior.
   - Check inline comments only for non-obvious why, constraints, tradeoffs, or gotchas.
   - Flag comments that merely restate the code.
   - End by confirming whether no further documentation changes are needed.

## Output

For each pass:

- Lead with findings, ordered by severity.
- Include exact file and line references when possible.
- Use `P1`, `P2`, or `P3` severity.
- Explain the concrete impact in one or two sentences.
- If there are no findings for that pass, say so directly.

After the documentation pass, give a short final summary with:

- Total findings by severity.
- Residual risk or validation gaps.
- Whether the PR is ready after the reported issues are addressed.
