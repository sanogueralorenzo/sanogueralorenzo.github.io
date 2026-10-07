# Instruction benchmarks

Compare focused prompts or skills with fixed inputs and bounded fixture tools, using the existing Codex login. Default replay fixtures never execute shell commands, edit real files, or contact services. Follow [PROTOCOL.md](PROTOCOL.md); [GUIDANCE.md](GUIDANCE.md) and [OUTCOMES.md](OUTCOMES.md) explain measured results and limits.

```sh
cd tools/assistant
npm run eval:benchmark -- plan evals/benchmark/suites/suggestions.json --variants live,contract_examples
npm run eval:benchmark -- run evals/benchmark/suites/suggestions.json --variants live,contract_examples --out ../../.precedent/assistant-benchmarks/development.json
node --experimental-strip-types evals/benchmark/judge.mjs ../../.precedent/assistant-benchmarks/development.json ../../.precedent/assistant-benchmarks/reviews.json high
npm run eval:benchmark -- report ../../.precedent/assistant-benchmarks/development.json --reviews ../../.precedent/assistant-benchmarks/reviews.json
```

Use `--split development|challenge|confirmation`, `--variants id,id`, `--repeats N`, and `--concurrency 1|2|3|4`. Run one suite at a time to avoid provider throttling. Before confirmation, run `freeze` with the final selection and identical settings, then `run --freeze manifest.json`. The prepared sets are exposed development/challenge data, including the initial confirmation cases. Author new families and add `datasets.confirmation` before another selection round.

Generation `--resume` requires unchanged instructions, cases, harness, and settings. For provider failures, `retry.mjs suite.json run.json` archives only infrastructure errors before resuming; semantic failures remain. Judge `--resume` preserves invalid batches and retries missing reviews under the same policy. Do not retry inconvenient semantic outcomes.

Suites define `id`, `mode` (`suggestion` or `agent`), `effort`, `datasets`, `variants` with instruction `files`, and optional skill `resources`. Cases define `id`, `family`, `category`, `messages`, `rubric`, and optional `tools`, `fixtures`, `initialState`, and `checks`. Fixture argument matching, validation, state effects, resources, and terminal outcomes are declarative. Checks support partial state, absent keys, exact JSON, required/prohibited calls (including arguments), explicit workflow order, and regex contracts. Mutable reads use `stateKey`; validators inspect `validateJSON` schemas. Flexible wording needs semantic review, not keyword matching.

Run the grader on `data/calibration/judge.json`, `speaker.json`, `confirmation.json`, `evidence.json`, and `integration.json` before trusting its judgments. Calibration gold is author-labelled; it is not independent human validation. `review run.json` exports an `inputHash`/`cards` packet accepted by the judge, with blinded cards with mode, context, rubric, visible trace, checks, and state. Review artifacts need the matching run's `inputHash`, named `provenance`, and complete `reviews`: `id`, `utility` (`useful|acceptable|missed|wrong|uncertain`), `constraints`, `confidence`, and `note`. Audit all uncertain and critical outcomes across variants. `adjudicate.mjs run.json reviews.json decisions.json output.json` preserves original grades and applies justified overrides from `{provenance, overrides: [{id, review, reason}]}`.

Reports separate utility, violations, failed outcome checks, provider failures, tokens, and deadlines, with paired family intervals and a local selection gate. A passing gate is evidence about these fixtures; real services, browser actions, and skill artifacts still need deployment checks. Raw runs are local under `.precedent/assistant-benchmarks`; never publish credentials or private conversation data.

Results-first suites set `minPairedFamilyMeanUtilityGain` and `minPairedFamily95PercentIntervalLow` alongside constraint and cost gates. Token savings alone cannot pass a required quality gain. `instruction-tokens.mjs spec.json output.json` measures provider input differences for `spec.prompts: [{id, files}]`, resolving files relative to the spec. Its explicit identical control and two repeats verify accounting; the result is not a standalone tokenizer count.

A demonstrated invalid assertion may be waived for an entire case with `checkWaivers: [{caseId, index, reason}]` in the adjudication decisions. The report retains waiver provenance; never waive a real semantic failure or only one variant.

`researcher-integration.json` runs on Pi Durable with Assistant’s shared production resource loader, model settings, native read/grep/find/ls tools, and hosted web search. It creates isolated workspaces in the OS temporary directory and checks their contents remain unchanged. It contacts public websites; raw results stay local. Cases combine actual Assistant source excerpts with authored projects, loaded AGENTS.md, and discoverable skills. These improve realism but are not representative user sampling.

`execution: "role-integration"` with `role: "coordinator"|"session"|"reviewer"` uses Durable conversations, production resources, and native tools in temporary workspaces. Session commands require exact `allowedCommands`; writes stay within the workspace. Browser and delegation results are fixtures. Coordinator uses actual HomeRouter with authored `homeState` and one current user message; it tests routing, not queue execution. These runners have local automated checks and fresh authored cases, but no provider confirmation run in this follow-up.
