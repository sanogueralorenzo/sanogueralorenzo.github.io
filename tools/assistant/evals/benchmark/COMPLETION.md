# Session completion evaluation

Retain all six production prompts. A new general session contract tested executing authorized work through verification, recovering from failures, and completing independent work when blocked. It replaced the session paragraph without adding examples; the shared base and all role boundaries stayed intact. The candidate did not qualify for fresh confirmation.

The [predeclared policy](policies/session-completion-v1.json) required a paired family utility gain of at least 0.05, a nonnegative 95% lower bound, preserved constraints, all required outcomes, no unresolved grading/provider failures, at most 5% mean workflow-token growth, and at most 10% combined instruction-input growth. One candidate was tested; no further prompt tuning follows from these outcomes.

| Measurement | Baseline | Candidate |
| --- | --- | --- |
| Useful replies / 24 | 20 | 21 |
| Mean utility, 0–2 | 1.708 | 1.750 |
| Mean complete-workflow tokens | 28,006 | 29,796 |
| Mean model requests | 4.292 | 4.583 |
| Mean tool rounds | 3.208 | 3.500 |
| Median latency | 13.21 s | 14.01 s |
| 90th percentile latency | 23.29 s | 20.47 s |
| Audited boundary violations | 0 | 2 |
| Failed required outcomes | 2 | 2 |

The paired family gain was 0.0417 [0, 0.125], below the quality threshold. Workflow tokens grew 6.39%, exceeding the guardrail. Instruction probes with an identical control and two rotated repeats measured 309 versus 335 incremental input tokens (+8.41%); these are provider accounting differences, not standalone tokenizer counts. No provider failures or deadline fallbacks occurred.

The 48 trials cover 12 authored development families: action requests, multipart work, partial blockers, missing preferences, previews, conditional no-ops, verification, unavailable checks, untrusted content, nested project rules, skills, and changed scope. Native reads, writes, edits and whitelisted commands use production Luna High resources and provider settings in isolated workspaces. Requested priority service was reported as default. Browser/delegation execution and representative production traffic remain unvalidated.

Grader agreement was 34/37 author-labelled controls. Two suggestion controls lack source content; another grading disagreement confused factual incorrectness with a boundary violation. Consequently, automated labels alone cannot support promotion. Primary-agent source review covered all task traces and saved-file snapshots, preserving original grades and one justified correction. A blanket bash prohibition incorrectly rejected a harmless read-only attempt; that assertion was waived across the entire case, with unchanged-file evidence retained. No actual semantic failure was waived.

A wording/rubric mismatch found during source review invalidated a partial run before selection; its raw outputs remain local. [Aggregate evidence](completion-evidence.json) records hashes, costs, checks and audits. Raw runs and credentials stay under ignored `.precedent/assistant-benchmarks/completion`. These are development diagnostics with model-assisted review, not independent human validation. No confirmation families were consumed and no production prompt changed.
