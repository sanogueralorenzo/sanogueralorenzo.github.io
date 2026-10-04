# Results-first prompt evaluation

Retain all six production prompts. Improve answer quality and complete-task reliability with concise, general instructions; prompt size and complete workflow cost are guardrails. Avoid accumulating examples or patches tailored to individual failures. The [current policy](RESULTS_POLICY.json) implements that objective; [aggregate evidence](outcome-evidence.json) preserves unsuccessful comparisons and audit corrections.

## Decisions

The initial compression diagnostic ran 280 development trials across coordinator, session, reviewer, researcher and suggestion roles. Smaller instructions did not establish a reliable quality gain. Session and reviewer edits mostly tied the baseline, researcher compression sometimes increased workflow tokens, and coordinator edits worsened routing. The shared base already receives skill-relative reference instructions from the production resource loader, so duplicating them adds no demonstrated benefit.

After the objective changed, two general coordinator revisions tested personal/project directory selection without adding examples. Each used six exposed development families, two variants and three repeats (36 trials). Independent blinded source audits covered all outcomes; original grades and justified corrections remain separate.

| Results-first candidate | Audited useful baseline / candidate | Paired mean utility change, 95% interval | Mean workflow tokens baseline / candidate | Decision |
| --- | --- | --- | --- | --- |
| Explicit project condition | 14/18 / 10/18 | −0.444 [−1.111, 0.111] | 861 / 784 | Reject: project routing regressed; personal directory leakage persisted |
| Personal rule first, original project semantics | 13/18 / 12/18 | −0.111 [−0.444, 0.222] | 776 / 819 | Reject: no quality gain; scope failures and cost growth |

Utility uses a 0–2 scale. Equal-weight family intervals describe these authored cases, not production performance. The frozen quality gates require at least 0.05 paired mean improvement, a 95% lower bound of zero, no candidate constraint violations or unresolved grading/infrastructure failures, and all required outcome checks. Guardrails allow at most 5% mean workflow-token growth and 10% combined instruction-input growth. Neither candidate qualified for confirmation. No production prompt or reasoning setting changed.

## Measurements and limits

Provider instruction probes used an explicit identical control and two rotated repeats. The final ordering candidate added two measured input tokens (about 0.46% of combined custom instructions), yet complete workflow cost rose about 5.64%. Counts relative to the control are not standalone tokenizer counts. Workflow totals include input, cached input and output; reasoning is reported separately as part of output, never added twice. Requested priority service was reported as default by the provider.

Eight fresh author-labelled grader controls passed, but source audits still corrected real-case grades. Review used Luna High and separate agent source audits, not independent human validation. One session scope judgment remains uncertain because the fixture never specified the working directory. All original grades, raw runs and audit decisions stay local under `.precedent/assistant-benchmarks`; the published JSON contains aggregates and hashes.

Researcher development used native reads and the production resource loader in isolated authored workspaces. Other development comparisons used bounded tool replay. Hosted search metadata does not prove a fetched HTTP response or page body. Actual SDK conversion preserved optional routing fields and emitted `strict: null`; provider-resolved schemas were not recorded, so these results establish no provider schema defect.

The reusable native role runner has focused automated tests for production assembly, real file outcomes, HomeRouter discovery, exact command whitelists and workspace boundaries. Browser and delegation actions remain fixture replies/errors. Its coordinator/session/reviewer cases have no provider confirmation results. The 117 independently authored fresh cases were source-audited before outcomes and never run for confirmation; once published, treat them as exposed regression/challenge inputs and author new families for a future selection.

Stop this comparison here. A future candidate needs a new general hypothesis and fresh frozen confirmation, rather than further tuning against these failures.
