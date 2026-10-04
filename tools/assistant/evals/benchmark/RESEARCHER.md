# Researcher improvement with native tools

The deployed researcher keeps its shared base, role, and Luna High setting. Its role now directs supplied-file reads, independent batching, use of relevant listed skills, reuse of loaded project instructions, a clear stopping point, and readable file-path citations. The [evidence](researcher-evidence.json) covers 408 valid trials and both rejected confirmation candidates. This is a scoped improvement, not an optimal prompt claim.

## Fresh confirmation

The final candidate was frozen before 128 runs: 32 new families, two repeats per prompt. The predeclared gate required at least 2% fewer total tokens, a paired 95% utility interval excluding loss greater than 0.1 on a 0–2 scale, zero candidate constraint violations, and no unresolved grading or outcome failures.

| Measure | Previous researcher | Deployed researcher |
| --- | ---: | ---: |
| Fully useful answers | 53/64 | 60/64 |
| Partially useful answers | 11/64 | 4/64 |
| Wrong answers / scope violations | 0 / 0 | 0 / 0 |
| Unusable native citation markers | 3 | 0 |
| Mean total tokens, including cached input | 17,879 | 17,400 |
| Mean provider requests | 2.94 | 2.80 |
| Median / p90 time | 9.14s / 13.41s | 8.63s / 12.21s |

Utility improved by 0.1094; the paired family interval was [0.0156, 0.2188]. The observed token saving was **2.68%**. Its exploratory cost interval still includes a small increase, so this does not establish a stable production cost reduction. Timings are descriptive. No final runs exhausted their budget or changed workspace files. The default production loader was checked against the exact frozen candidate.

The final custom instructions grew from 220 to 269 words, including the unchanged 184-word base. The gain comes from workflow and output behavior, not fewer instruction words.

## Realism and review

The runner uses the production resource loader, provider setup, native read/grep/find/ls tools, and actual hosted search. Cases include copied Assistant source, loaded AGENTS.md, discoverable skills and relative references, missing evidence, conflicting documentation, strict output formats, untrusted content, and privacy boundaries. Workspaces are isolated in the OS temporary directory; hashes verify file preservation.

Across the development and three confirmation sets, tasks range from terse questions to roughly 32,000 characters, with source workspaces reaching over 41,000 characters. Writing includes clean requests, typos, messy handoffs, Spanish, OCR, minified code, and noisy logs. The final set spans 25–17,265 task characters but is weighted toward short questions: 25 of 32 are at most 100 characters, five are 101–500, one is 501–3,000, and one is longer. These are authored cases, not representative user sampling. Results for longer tasks are especially limited.

Luna High reviewed blinded outputs; the primary agent audited every confirmation answer and critical tool traces. This is not independent human validation. Five additional calibration controls matched usefulness 5/5 but constraints 4/5, reinforcing the need for audits. Corrections preserve original grades and explain whole-family contract errors. Missing helpful citations remain partial, rather than becoming false factual failures.

The final audit retained wrong skill-relative-path attempts in all four missing-reference runs, an inaccurate date-order example, underspecified object-identity explanations, missing references, and an overconfident join inference. None was hidden to pass the gate. Three malformed-ID grader batches were preserved; two missing reviews received explicit primary-agent grades. Immutable review packets were verified against the complete run before merging.

## What failed and what transfers

A compact base that saved 20.4% in earlier replay fixtures did not improve native-tool development cost. A self-contained researcher candidate saved 11.1% on its first fresh confirmation but failed the quality margin. Preserving the base and adding workflow guidance saved 7.8% on the next fresh set, but citation defects again failed the quality margin. The final candidate added a short requirement for readable local file paths, addressing that observed defect before a third fresh set.

Twenty-six early trials were excluded because placing workspaces under ignored `.precedent` changed native file discovery. Three stale provider-error flags in the first confirmation were corrected only after SDK retries produced completed answers; raw events and hashes remain preserved. The existing production renderer removed empty web-citation markers. Hosted-fetch bodies/statuses are not exposed, so four inaccessible-URL answers retained partial utility for unverified status-code details.

Reusable directions supported here:

- Measure complete workflows and renderer-visible output. Cutting instructions can add discovery calls; a small addition can reduce them.
- Share actual resource/provider/tool setup with evaluation. Replay savings may disappear with real file discovery and loaded instructions.
- Resolve observed failure classes with explicit contracts, then use fresh families. Do not keep editing against the same confirmation set.
- Audit sources and critical traces across every variant. Graders missed existing references, invented extra requirements, and confused inference errors with scope violations.
- Keep role transfer separate. These results do not establish a rewrite for suggestions, reviewer, coordinator, session, or arbitrary skills.

All used confirmation cases are now challenge data in `researcher-integration.json`. Add fresh families before freezing another selection. Use [PROTOCOL.md](PROTOCOL.md) for prompts or skills; skills also require trigger boundaries, relative references, saved-artifact validation, and user overrides. Raw runs, credentials, transport errors, and local reviews stay ignored; published evidence contains aggregate results and hashes.
