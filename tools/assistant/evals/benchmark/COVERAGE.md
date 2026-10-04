# Coverage and limits

The authored task population covers short Assistant follow-ups and bounded local agent decisions. It is not a random sample of users. Related email paraphrases share a family. The older 36 suggestion cases, including their former heldout set, are regression data only.

| Experiment | Declared variation | Cases / repetitions |
| --- | --- | --- |
| Suggestion development | Live, two compact contracts, with/without examples, paragraph, bullets, tags, example placement, minimal negative control | 18 / 3 |
| Suggestion challenge | Live and two fixed compact finalists | 12 / 5 |
| Suggestion confirmation | Same frozen finalists; no candidate edits | 24 / 5 |
| Reasoning diagnostic | Live and example contract × none, low, high | 6 reused challenge families / 5 |
| Coordinator, researcher, reviewer, session | Live, shorter base, shorter role | 6 development / 3 per role |
| Role confirmation | Live and one fixed finalist per role | 6 new families / 3 per role |
| Sample skill | Full, compact, minimal negative control | 8 development / 3 |
| Skill confirmation | Full and compact, same underlying agent | 8 new families / 3 |

Suggestions cover sole offers, chosen options, conflicting recommendations, changed scope, outstanding checks, false completion, arithmetic discrepancies, missing personal information, completed work, another language, quoted role attacks, and long/noisy input. Agent cases cover destination selection, explicit versus implicit context, source evidence, denied access, scoped changes, preserved user content, previews, no-op conditions, and misleading source content. Skill cases add triggers, nontriggers, loaded instructions/references, exact artifact keys, validation, user overrides, missing input, denied references, and untrusted notes.

Freeze instructions, resources, cases, grader policy, repeats, and settings before confirmation. Use a 0.1 maximum utility loss on the 0–2 scale, at least 10% mean total-token savings, and no unresolved constraint violations. Review uncertainty and failed checks before selection. These are local experiment thresholds, not universal product tolerances.

The suggestion harness matches production context truncation, model, reasoning, tool isolation, and five-second deadline measurement. It measures eventual output for diagnosis after that deadline; late suggestions are not delivered by production. Agent fixtures use the deployed role/base wording and reasoning but a smaller tool set, frozen sources, no live web/browser, and no real workspace. The sample skill is a fixture, not a validation of any installed skill. Missing deployment categories prohibit treating a role result as approval to replace the shared base globally.

Stop after this matrix, grader calibration, failure audits, and frozen confirmation. Retain the baseline when evidence is insufficient. Adding paraphrases until a preferred candidate passes is not an acceptable stopping rule. Language compression, other model families, actual renderer/browser integrations, and representative production sampling need separate hypotheses and fresh confirmation; this matrix establishes no conclusions about them.

The published confirmation cases are now exposed challenge/regression inputs. The comparison counts above describe the archived initial study; new selection rounds must supply new confirmation families. The incomplete-output reasoning case is corrected in regression data, with its original 30 observations retained as uncertain for historical usefulness comparisons.
