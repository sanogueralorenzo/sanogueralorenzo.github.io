# Evidence-backed instruction improvements

Keep the current suggestion prompt. This study does not establish an optimal prompt, but it rejects two tempting compression candidates and provides a reusable evaluation method. The [evidence summary](evidence.json) records 1,794 model trials (30 remain uncertain for usefulness) across 14 comparisons, prompt/resource hashes, settings, family intervals, calibrated model review, and audit corrections. [Coverage](COVERAGE.md) defines the tested population and gaps.

Output-quality counts describe eventual replies; deadline fallbacks are reported separately.

## What the measurements support

| Comparison | Observed result | Decision |
| --- | --- | --- |
| Suggestions: live, 177 words | 117/120 useful; 3 missed; no wrong replies observed | Retain |
| Suggestions: compact, 113 words | 102 useful, 1 acceptable, 11 missed, 6 wrong; 27.2% fewer total tokens | Reject |
| Suggestions: contract with examples, 130 words | 116 useful, 3 missed, 1 wrong; 21.7% fewer total tokens | Reject; usefulness interval includes more than the allowed loss |
| Researcher: shorter base | Same constraints preserved in 18 confirmation trials; 20.4% fewer tokens, better source attribution | Promising local fixture result |
| Session: shorter base | Both variants useful in all 18 confirmation trials; 22.6% fewer tokens | Promising local fixture result |
| Coordinator: shorter role | More wrong destinations; 14.4% fewer tokens | Reject |
| Reviewer: shorter role | Correct findings with slightly better attribution; only 0.3% fewer tokens | No material cost saving established |
| Sample skill: compact instructions | 20 useful, 2 partial, 2 unfinished versus 24 useful; 6.9% **more** tokens | Retain full workflow |

Role results have six confirmation families each; the skill has eight. These are authored pilots, not production distributions. A zero observed violation count and a degenerate bootstrap interval do not prove zero risk. The shared base covers deployed tools and repository context that these fixtures omit, so no global base replacement follows from the researcher/session results. Production prompts and reasoning remain unchanged.

The reasoning diagnostic compared none, low, and high on six reused challenge families. One completion case lacked the referenced earlier output; all 30 trials for that family are uncertain and excluded from usefulness comparisons. On the remaining five families there is insufficient evidence to select a new reasoning setting. High's observed median took roughly 4.1–4.3 seconds, versus roughly 1.4–1.5 seconds for none, and crossed the five-second hint deadline in 9–10/30 trials versus 0–1/30. These are model-loop observations; requested priority service was reported as default by the provider.

## Reuse these directions

1. **Specify the actor and task contract.** A next-user-message predictor must not answer as the assistant. Our first grader confused valid commands with unperformed work and accepted wrong-speaker requests. Calibrating that distinction changed which candidates looked safe. For another role, define its own input, authority, allowed actions, output, and completion conditions.
2. **Compress only against measured outcomes.** The example contract was perfect on development and still failed fresh confirmation. Paragraphs, bullets, tags, and example placement established no consistent quality advantage. Do not assume repetition is useless or that a formatting change preserves behavior. Test deletions separately before combining them.
3. **Measure the complete workflow.** Count all request tokens, output/reasoning tokens, tool rounds, and deadline fallbacks. Shorter skill instructions caused wrong reference-path attempts and extra calls. Fewer instruction words can cost more overall.
4. **Preserve observable obligations.** Skills need trigger/nontrigger cases, loaded instructions/references, user overrides, saved artifact checks, and honest failure handling. A correct-looking artifact can still omit a required workflow step. A user-supplied replacement schema can also legitimately supersede a default step; do not enforce the obsolete step.
5. **Evaluate the evaluator and environment.** Read-after-write must return current state. Validation must inspect the saved artifact and occur after its final write. Missing citations are partial utility, not false diagnoses. Unclear context stays uncertain rather than becoming a failure. Audit whole case families across every variant and preserve original grades and rationale.
6. **Keep confirmation independent.** Freeze candidates, grading rules, and selection margins before outputs. Repeated trials measure variability, not additional independent tasks. Once exposed, confirmation cases become regression data; publish failures and keep the baseline when no candidate passes.

These methodological directions align with [OpenAI's evaluation guidance](https://developers.openai.com/api/docs/guides/evaluation-best-practices) and [Anthropic's agent evaluation guidance](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents). Their documentation supports the process, not superiority of our particular rewrites.

## Starting structure, not a proven optimum

For a focused agent, start with a short task statement, relevant constraints, missing-input/failure behavior, observable completion, and output format. Add examples only for confusions the evaluation actually detects. For a skill, also make trigger boundaries and reference resolution explicit. Shared instructions should contain rules proven common across the deployed roles; revalidate role-specific changes separately.

All semantic review here used Luna High and primary-agent audits. The 32 author-labelled calibration controls passed, yet real-case audits still found errors. Independent human calibration, representative production sampling, repository/skill context, hosted search, browser work, and real artifact/rendering checks remain necessary for stronger deployment claims. No result here establishes benefits from Chinese instruction compression or other model families.
