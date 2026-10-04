# Prompt and skill evaluation

Evaluate the task contract, not a preferred sentence or tool sequence. Separate useful output, harmless abstention, wrong output, scope violations, infrastructure errors, and deadline fallbacks. Fewer tokens are a secondary objective.

## Before running

1. Specify the deployed model, reasoning level, context assembly, tools, output contract, deadline, and task population. Record differences between the fixture harness and production.
2. Create development, challenge, and confirmation sets. Group related paraphrases under one family. Cover ordinary requests, ambiguous intent, changing scope, missing information, completed work, long context, and untrusted content. Test tools and artifacts for agents and skills.
3. Define acceptable outcomes, including multiple valid answers and acceptable abstentions. Mark explicit forbidden actions separately. Calibrate graders on useful paraphrases, harmless omissions, wrong approvals, and misleading completion claims.
4. Freeze candidate instructions, case families, grading policy, and selection margins before seeing confirmation outputs. New edits require a new confirmation set; a used confirmation set becomes development data. Authored cases are not representative production samples merely because they are new.

## Compare

Run paired trials on identical inputs. Rotate request order, repeat trials, isolate state, and record model identity, prompt and resource hashes, tools, provider effort/tier, cache usage, full trace, outcome, tokens, and deadlines. Include unchanged controls. Test one deletion at a time; verify combinations separately. Layout and word counts do not establish token counts or behavioral equivalence.

Use deterministic checks for exact destinations, schemas, bounded fixture outcomes, and prohibited actions. Use blinded rubric review for meaning; expose the conversation and rubric, but hide variant names, prompt length, timing, and cost. Calibrate any model grader before relying on it. Preserve low-confidence reviews for adjudication rather than silently treating them as ground truth. Exclude unresolved utility judgments from utility estimates; report their count. An invalid assertion may be waived only with explicit rationale for the whole case across variants. If a broken tool fixture influenced model behavior, invalidate its comparisons and rerun under a corrected environment. Agent-assisted review is not independent human validation.

Aggregate by case and family; repeated trials are not additional independent tasks. Report paired case-level differences and bootstrap intervals, category-level results, and constraint violations separately. Do not claim improvement from isolated misses, identical totals, or a confidence interval spanning material harm. A zero observed violation count does not establish zero production risk.

## Select and stop

Select at most two development finalists before confirmation. Prefer a shorter candidate only when confirmation preserves constraints, satisfies the predeclared usefulness margin, and achieves a worthwhile measured reduction. Reject candidates with unresolved critical violations, uncertain grading, or mismatched production settings. Otherwise retain the baseline and report that evidence is insufficient.

Stop when every declared variation class and task category has coverage, graders and harness checks pass, frozen finalists complete confirmation, disagreements and critical failures are reviewed, and conclusions have explicit evidence and limits. Exhausting an infinite space of prompts is impossible. Further experiments need a new hypothesis, unresolved failure, or materially different deployment.

## Transfer

Repeat confirmation for each role, model, tool boundary, and skill workflow. A tool-free suggestion result is not evidence for a tool-using agent. Fixture tool replay tests instruction decisions; it does not validate real services, browser interaction, file renderers, or resource loading. Use deployment integration checks for those outcomes. Skills additionally need trigger, non-trigger, instruction-loading, reference-loading, output-artifact, and user-override cases.

Methods: [OpenAI evaluation guidance](https://developers.openai.com/api/docs/guides/evaluation-best-practices), [Anthropic agent evaluation guidance](https://www.anthropic.com/engineering/demystifying-evals-for-ai-agents). These support the evaluation method; they do not prove a specific prompt rewrite improves this application.
