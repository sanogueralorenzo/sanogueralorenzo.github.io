# Voice Engine API Contract

This document defines the stable deterministic contract shared by all Voice
platforms. Android, iOS, macOS, and web bindings may expose platform-native
types, but they must preserve the same operation names, values, ordering, and
fallback behavior.

The engine is synchronous and deterministic. It owns text normalization,
pre-LLM compose rules, post-LLM compose guardrails, edit command parsing,
deterministic edit application, list detection, and replacement casing.
Platforms own ASR, UI, LLM runtime invocation, persistence, lifecycle, and
telemetry.

## Common Values

Rule IDs are stable uppercase strings. They are emitted in first-application
order and de-duplicated by rule ID.

Preprocess rule order:

1. `FILLER`
2. `ADJACENT_DUPLICATE`
3. `MINUTES_NORMALIZATION`
4. `CORRECTION_TURN`
5. `NUMBER_WORDS_TO_DIGITS`

Edit intent values:

- `GENERAL`
- `DELETE_ALL`
- `REPLACE`

Command scope values:

- `ALL`
- `FIRST`
- `LAST`

Command kind values:

- `NO_OP`
- `CLEAR_ALL`
- `DELETE_TERM`
- `REPLACE_TERM`
- `UPDATE_NUMBER`

Rule confidence values:

- `HIGH`
- `LOW`

JNI string encodings use U+001F as the internal field separator. Fields that can
contain user text must replace U+001F with a space before crossing the JNI
boundary. Platform APIs should expose structured values instead of this encoded
format.

## Operations

### `preprocess(input)`

Applies deterministic compose input rules before any LLM call.

Input:

- `input`: nullable only at binding boundaries. Core Rust accepts `&str`;
  Android exposes non-null `String`.

Output:

- `text`: trimmed and surface-cleaned output.
- `changed`: `true` when `text` differs from `input.trim()`.
- `appliedRuleIds`: ordered set of rule IDs from the preprocess rule list.

Behavior:

- Blank or whitespace-only input returns `text=""`, `changed=false`, and no
  rule IDs.
- Rules are evaluated in the fixed preprocess order above.
- Rule IDs are reported only when that rule changes the intermediate text.

### `normalize_compose_input(text)`

Normalizes raw compose text before entering the compose rewrite path.

Output:

- Collapses whitespace.
- Removes spaces before punctuation.
- Collapses repeated filler and punctuation artifacts.
- Returns `""` for blank input.

### `normalize_instruction_input(text)`

Normalizes an edit instruction before edit analysis or LLM edit.

Output:

- Collapses whitespace and trims leading/trailing whitespace.
- Returns `""` for blank input.

### `clean_model_output(text, bullet_mode)`

Cleans raw model output before it is used as final text or passed to compose
guardrails.

Output:

- Returns `""` for blank or unusable output.
- Removes labels such as `cleaned:`, `output:`, and surrounding quotes/backticks.
- If `bullet_mode=false`, flattens `- ` bullet lines into prose.
- Applies sentence capitalization and spoken-number normalization through
  `normalize_compose_output_text`.
- If `bullet_mode=true`, preserves bullet/newline shape while still applying
  output cleanup.

### `normalize_compose_output_text(text)`

Normalizes trusted compose output.

Output:

- Trims whitespace.
- Sentence-capitalizes the first word and words after configured punctuation.
- Converts unambiguous spoken number phrases to digits.
- Returns `""` for blank input.

### `postprocess(original_text, model_output, list_mode)`

Final compose guardrail after an LLM rewrite.

Behavior:

- Cleans `model_output` with `clean_model_output(model_output, list_mode)`.
- If `original_text.trim()` is blank, returns the cleaned candidate.
- If the cleaned candidate is blank, returns `original_text.trim()`.
- Rejects and falls back to `original_text.trim()` when the candidate looks like
  an assistant reply, changes length too much, or has low token overlap.
- Otherwise returns the cleaned candidate.

### `analyze_instruction(instruction_text)`

Classifies an edit instruction and returns a normalized command candidate.

Output:

- `normalizedInstruction`: whitespace-normalized instruction with command
  preambles and correction turns resolved where supported.
- `intent`: one of `GENERAL`, `DELETE_ALL`, or `REPLACE`.

Behavior:

- Clear-all commands produce `DELETE_ALL`.
- Replace-term and update-number commands produce `REPLACE`.
- Everything else produces `GENERAL`.
- Blank input produces `normalizedInstruction=""` and `intent=GENERAL`.

### `is_strict_edit_command(instruction_text)`

Returns whether an instruction is safe to route through the edit path without
needing broader natural-language interpretation.

Behavior:

- Returns `true` for start-anchored no-op, delete, clear-all, replace, and
  update-number commands.
- Returns `false` for blank input, general rewrite requests, and loose
  conversational text that merely contains an edit verb.

### `should_allow_blank_output(intent)`

Returns whether a blank edit result may be committed.

Behavior:

- Returns `true` only for `DELETE_ALL`.
- Returns `false` for `GENERAL` and `REPLACE`.

### `try_apply_deterministic_edit(source_text, instruction_text)`

Attempts to apply a strict edit command without an LLM.

Output:

- Returns `null`/`None` when input is blank, command gating fails, the command is
  ambiguous, or no single deterministic command can be parsed.
- Returns a deterministic edit result with:
  - `output`
  - `applied`
  - `intent`
  - `scope`
  - `commandKind`
  - `matchedCount`
  - `ruleConfidence`
  - `noMatchDetected`

Behavior:

- Parse order is no-op, clear-all, delete-term, replace-term, update-number.
- Exactly one command must parse; competing parses return `null`/`None`.
- `NO_OP` returns the original source, `applied=false`, `matchedCount=1`,
  `ruleConfidence=HIGH`, `noMatchDetected=false`.
- `CLEAR_ALL` returns `""`, `intent=DELETE_ALL`, `scope=ALL`, and
  `commandKind=CLEAR_ALL`.
- Delete and replace commands honor `FIRST`, `LAST`, and `ALL` when present.
- Multiple delete targets are only accepted with `ALL` scope.
- No target match returns the original source with `ruleConfidence=LOW` and
  `noMatchDetected=true`.

### `looks_like_list(text)`

Detects whether text should be treated as list-like for formatting and cleanup.

Behavior:

- Returns `false` for blank input.
- Returns `true` for explicit bullets, numbered list cues, shopping/task cues
  with delimited items, compact multi-line item lists, or four-plus short
  delimiter-separated items.
- Returns `false` for ordinary prose.

### `post_replace_capitalization(source_text, instruction_text, edited_output)`

Restores replacement casing after an LLM edit when a replace command targets a
capitalized source term.

Behavior:

- Returns `edited_output` unchanged if any input is blank, the instruction is not
  a deterministic replace command, the target is missing from the source, or the
  source target is not capitalized.
- When the source target is capitalized, matching replacement terms in
  `edited_output` inherit that casing.

## Error And Null Behavior

Core Rust operations do not throw for normal malformed user text. Unsupported or
ambiguous edit commands return `None`. Blank text returns empty strings or
`false` according to each operation above.

Android exposes non-null `String` parameters. JNI conversion failures are treated
as empty input. Encoded JNI result strings that are blank or malformed are
treated as `null` deterministic edit results by the Kotlin binding.
