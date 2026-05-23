use jni::objects::{JClass, JString};
use jni::sys::{jboolean, jstring};
use jni::JNIEnv;
use once_cell::sync::Lazy;
use regex::{Captures, Regex};
use std::ops::Range;

pub struct PreprocessResult {
    pub text: String,
    pub changed: bool,
    pub applied_rules: Vec<&'static str>,
}

pub fn preprocess(input: &str) -> PreprocessResult {
    let source = input.trim();
    if source.is_empty() {
        return PreprocessResult {
            text: String::new(),
            changed: false,
            applied_rules: Vec::new(),
        };
    }

    let mut current = source.to_string();
    let mut applied_rules = Vec::new();

    apply_pre_rule(
        &mut current,
        "FILLER",
        remove_standalone_fillers,
        &mut applied_rules,
    );
    apply_pre_rule(
        &mut current,
        "ADJACENT_DUPLICATE",
        collapse_adjacent_duplicates,
        &mut applied_rules,
    );
    apply_pre_rule(
        &mut current,
        "MINUTES_NORMALIZATION",
        normalize_minutes,
        &mut applied_rules,
    );
    apply_pre_rule(
        &mut current,
        "CORRECTION_TURN",
        resolve_correction_turns,
        &mut applied_rules,
    );
    apply_pre_rule(
        &mut current,
        "NUMBER_WORDS_TO_DIGITS",
        number_words_to_digits,
        &mut applied_rules,
    );

    let final_text = surface_cleanup(&current);
    PreprocessResult {
        text: final_text.clone(),
        changed: final_text != source,
        applied_rules,
    }
}

pub fn normalize_compose_input(text: &str) -> String {
    let collapsed = WHITESPACE.replace_all(text, " ").trim().to_string();
    if collapsed.is_empty() {
        return String::new();
    }
    collapse_repeated_punctuation(
        SPACE_BEFORE_PUNCTUATION
            .replace_all(&collapse_repeated_fillers(&collapsed), "$1")
            .as_ref(),
    )
    .trim()
    .to_string()
}

pub fn normalize_instruction_input(text: &str) -> String {
    WHITESPACE.replace_all(text, " ").trim().to_string()
}

pub fn clean_model_output(text: &str, bullet_mode: bool) -> String {
    let mut cleaned = text.trim().to_string();
    if cleaned.is_empty() {
        return String::new();
    }

    if let Some(anchor) = CLEANED_ANCHOR.find_iter(&cleaned).last() {
        cleaned = cleaned[anchor.end()..].trim().to_string();
    }

    cleaned = PREFIX_LABEL.replace(&cleaned, "").trim().to_string();
    cleaned = cleaned.trim_matches('`').trim().to_string();
    cleaned = remove_surrounding_pair(&cleaned, '"', '"');
    cleaned = remove_surrounding_pair(&cleaned, '\'', '\'');
    cleaned = cleaned.trim().to_string();
    if cleaned.is_empty() {
        return String::new();
    }

    if cleaned.to_lowercase().starts_with("user input:") {
        let non_empty_lines: Vec<&str> = cleaned
            .lines()
            .map(str::trim)
            .filter(|line| !line.is_empty())
            .collect();
        if non_empty_lines.len() >= 2 {
            cleaned = non_empty_lines.last().unwrap().to_string();
        }
    }

    if !bullet_mode && cleaned.starts_with("- ") {
        cleaned = cleaned
            .lines()
            .map(|line| line.trim().strip_prefix("- ").unwrap_or(line.trim()).trim())
            .filter(|line| !line.is_empty())
            .collect::<Vec<&str>>()
            .join(" ");
    }

    normalize_compose_output_text(&cleaned)
}

pub fn normalize_compose_output_text(text: &str) -> String {
    let trimmed = text.trim();
    if trimmed.is_empty() {
        return String::new();
    }
    spoken_numbers_to_digits(&sentence_capitalize(trimmed))
}

pub fn postprocess(original_text: &str, model_output: &str, list_mode: bool) -> String {
    let original = original_text.trim();
    let candidate = clean_model_output(model_output, list_mode)
        .trim()
        .to_string();
    choose_guarded_output(original, &candidate)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum EditIntent {
    General,
    DeleteAll,
    Replace,
}

impl EditIntent {
    fn as_str(self) -> &'static str {
        match self {
            EditIntent::General => "GENERAL",
            EditIntent::DeleteAll => "DELETE_ALL",
            EditIntent::Replace => "REPLACE",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CommandScope {
    All,
    First,
    Last,
}

impl CommandScope {
    fn as_str(self) -> &'static str {
        match self {
            CommandScope::All => "ALL",
            CommandScope::First => "FIRST",
            CommandScope::Last => "LAST",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CommandKind {
    NoOp,
    ClearAll,
    DeleteTerm,
    ReplaceTerm,
    UpdateNumber,
}

impl CommandKind {
    fn as_str(self) -> &'static str {
        match self {
            CommandKind::NoOp => "NO_OP",
            CommandKind::ClearAll => "CLEAR_ALL",
            CommandKind::DeleteTerm => "DELETE_TERM",
            CommandKind::ReplaceTerm => "REPLACE_TERM",
            CommandKind::UpdateNumber => "UPDATE_NUMBER",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RuleConfidence {
    High,
    Low,
}

impl RuleConfidence {
    fn as_str(self) -> &'static str {
        match self {
            RuleConfidence::High => "HIGH",
            RuleConfidence::Low => "LOW",
        }
    }
}

pub struct EditInstructionAnalysis {
    pub normalized_instruction: String,
    pub intent: EditIntent,
}

pub struct DeterministicEditResult {
    pub output: String,
    pub applied: bool,
    pub intent: EditIntent,
    pub scope: CommandScope,
    pub command_kind: CommandKind,
    pub matched_count: usize,
    pub rule_confidence: RuleConfidence,
    pub no_match_detected: bool,
}

#[derive(Clone)]
struct ParsedCommand {
    kind: CommandKind,
    scope: CommandScope,
    target: Option<String>,
    replacement: Option<String>,
}

struct ScopedTarget {
    scope: CommandScope,
    target: String,
}

struct ReplaceApplyResult {
    output: String,
    matched_count: usize,
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum DeleteVerbRestriction {
    AllOnly,
    TargetedOnly,
}

#[derive(Clone, Copy, Eq, PartialEq)]
enum ReplaceVerbRestriction {
    ExcludeNumberTarget,
}

#[derive(Clone, Copy)]
enum ReplaceConnector {
    With,
    To,
    For,
}

impl ReplaceConnector {
    fn pattern(self) -> &'static str {
        match self {
            ReplaceConnector::With => "with",
            ReplaceConnector::To => "to",
            ReplaceConnector::For => "for",
        }
    }
}

struct DeleteVerbSpec {
    pattern: &'static str,
    bare_means_all: bool,
    restrictions: &'static [DeleteVerbRestriction],
}

struct ReplaceVerbSpec {
    pattern: &'static str,
    connectors: &'static [ReplaceConnector],
    restrictions: &'static [ReplaceVerbRestriction],
}

pub fn analyze_instruction(instruction_text: &str) -> EditInstructionAnalysis {
    let collapsed = WHITESPACE
        .replace_all(instruction_text, " ")
        .trim()
        .to_string();
    let normalized = normalize_correction_phrases(&collapsed);
    let command_candidate = strip_command_preamble(&normalized);
    let delete_command = parse_delete_verb_command(&command_candidate);
    let replace_command = parse_replace_command(&command_candidate);
    let update_number_command = parse_update_number_command(&command_candidate);
    let intent = if delete_command
        .as_ref()
        .is_some_and(|command| command.kind == CommandKind::ClearAll)
    {
        EditIntent::DeleteAll
    } else if replace_command.is_some() || update_number_command.is_some() {
        EditIntent::Replace
    } else {
        EditIntent::General
    };
    EditInstructionAnalysis {
        normalized_instruction: command_candidate,
        intent,
    }
}

pub fn is_strict_edit_command(instruction_text: &str) -> bool {
    let collapsed = WHITESPACE
        .replace_all(instruction_text, " ")
        .trim()
        .to_string();
    if collapsed.is_empty() {
        return false;
    }
    let command_candidate = strip_command_preamble(&collapsed);
    if command_candidate.is_empty() {
        return false;
    }
    parse_delete_verb_command(&command_candidate).is_some()
        || NO_OP.is_match(&command_candidate)
        || parse_replace_command(&command_candidate).is_some()
        || parse_update_number_command(&command_candidate).is_some()
}

pub fn should_allow_blank_output(intent: EditIntent) -> bool {
    intent == EditIntent::DeleteAll
}

pub fn try_apply_deterministic_edit(
    source_text: &str,
    instruction_text: &str,
) -> Option<DeterministicEditResult> {
    if source_text.trim().is_empty() || instruction_text.trim().is_empty() {
        return None;
    }
    let analysis = analyze_instruction(instruction_text);
    let command_candidate = analysis.normalized_instruction;
    if !passes_command_gate(&command_candidate) {
        return None;
    }

    let parsed = parse_deterministic_command(&command_candidate)?;
    match parsed.kind {
        CommandKind::NoOp => Some(DeterministicEditResult {
            output: source_text.to_string(),
            applied: false,
            intent: EditIntent::General,
            scope: CommandScope::All,
            command_kind: CommandKind::NoOp,
            matched_count: 1,
            rule_confidence: RuleConfidence::High,
            no_match_detected: false,
        }),
        CommandKind::ClearAll => Some(DeterministicEditResult {
            output: String::new(),
            applied: !source_text.is_empty(),
            intent: EditIntent::DeleteAll,
            scope: CommandScope::All,
            command_kind: CommandKind::ClearAll,
            matched_count: usize::from(!source_text.is_empty()),
            rule_confidence: RuleConfidence::High,
            no_match_detected: false,
        }),
        CommandKind::DeleteTerm => {
            let target = parsed.target.unwrap_or_default();
            let targets = split_delete_targets(&target);
            if targets.len() > 1 && parsed.scope != CommandScope::All {
                return None;
            }
            let mut updated = source_text.to_string();
            let mut total_matched = 0usize;
            for term in targets {
                let replace_result = apply_scoped_edit(
                    &updated,
                    &term,
                    "",
                    if target.contains(',') || DELETE_TARGET_SEPARATOR.is_match(&target) {
                        CommandScope::All
                    } else {
                        parsed.scope
                    },
                );
                updated = replace_result.output;
                total_matched += replace_result.matched_count;
            }
            let output = cleanup_edited_text(&updated);
            Some(DeterministicEditResult {
                applied: updated != source_text,
                output,
                intent: EditIntent::General,
                scope: parsed.scope,
                command_kind: CommandKind::DeleteTerm,
                matched_count: total_matched,
                rule_confidence: if total_matched > 0 {
                    RuleConfidence::High
                } else {
                    RuleConfidence::Low
                },
                no_match_detected: total_matched == 0,
            })
        }
        CommandKind::ReplaceTerm => {
            let target = parsed.target.unwrap_or_default();
            let replacement = parsed.replacement.unwrap_or_default();
            let replace_result =
                apply_scoped_edit(source_text, &target, &replacement, parsed.scope);
            let output = cleanup_edited_text(&replace_result.output);
            Some(DeterministicEditResult {
                applied: replace_result.output != source_text,
                output,
                intent: EditIntent::Replace,
                scope: parsed.scope,
                command_kind: CommandKind::ReplaceTerm,
                matched_count: replace_result.matched_count,
                rule_confidence: if replace_result.matched_count > 0 {
                    RuleConfidence::High
                } else {
                    RuleConfidence::Low
                },
                no_match_detected: replace_result.matched_count == 0,
            })
        }
        CommandKind::UpdateNumber => {
            let replacement = parsed.replacement.unwrap_or_default();
            let replace_result = apply_last_numeric_edit(source_text, &replacement);
            let output = cleanup_edited_text(&replace_result.output);
            Some(DeterministicEditResult {
                applied: replace_result.output != source_text,
                output,
                intent: EditIntent::Replace,
                scope: CommandScope::Last,
                command_kind: CommandKind::UpdateNumber,
                matched_count: replace_result.matched_count,
                rule_confidence: if replace_result.matched_count > 0 {
                    RuleConfidence::High
                } else {
                    RuleConfidence::Low
                },
                no_match_detected: replace_result.matched_count == 0,
            })
        }
    }
}

pub fn looks_like_list(text: &str) -> bool {
    let input = text.trim();
    if input.is_empty() {
        return false;
    }
    if EXPLICIT_BULLET.is_match(input) || LIST_CUE.is_match(input) {
        return true;
    }
    if SHOPPING_TASK_CUE.is_match(input) && DELIMITED_ITEMS.is_match(input) {
        return true;
    }
    let newline_segments: Vec<&str> = input
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty())
        .collect();
    if newline_segments.len() >= 3
        && newline_segments
            .iter()
            .filter(|line| line.len() <= 32)
            .count()
            >= 2
    {
        return true;
    }
    let delimiter_count = input
        .chars()
        .filter(|value| matches!(value, ',' | ';' | '|'))
        .count();
    if delimiter_count >= 3 {
        let tokens: Vec<&str> = input
            .split([',', ';', '|'])
            .map(str::trim)
            .filter(|token| !token.is_empty())
            .collect();
        if tokens.len() >= 4 {
            let avg_len =
                tokens.iter().map(|token| token.len()).sum::<usize>() as f32 / tokens.len() as f32;
            if avg_len <= 18.0 {
                return true;
            }
        }
    }
    false
}

pub fn post_replace_capitalization(
    source_text: &str,
    instruction_text: &str,
    edited_output: &str,
) -> String {
    if source_text.trim().is_empty()
        || instruction_text.trim().is_empty()
        || edited_output.trim().is_empty()
    {
        return edited_output.to_string();
    }
    let parsed = replacement_terms_for_post_capitalization(instruction_text);
    let Some((target, replacement)) = parsed else {
        return edited_output.to_string();
    };
    let source_matches = find_target_matches(source_text, &target);
    let capitalized_source_match = source_matches
        .iter()
        .find(|range| is_capitalized_word_match(&source_text[range.start..range.end]));
    let Some(capitalized_source_match) = capitalized_source_match else {
        return edited_output.to_string();
    };
    let source_match = source_text[capitalized_source_match.clone()].to_string();
    replace_target_matches(edited_output, &replacement, |matched| {
        apply_replacement_casing(&source_match, matched)
    })
}

fn replacement_terms_for_post_capitalization(instruction_text: &str) -> Option<(String, String)> {
    if instruction_text.trim().is_empty() {
        return None;
    }
    let command_candidate = analyze_instruction(instruction_text).normalized_instruction;
    let parsed = parse_deterministic_command(&command_candidate)?;
    if parsed.kind != CommandKind::ReplaceTerm {
        return None;
    }
    let target = parsed.target.unwrap_or_default();
    let replacement = parsed.replacement.unwrap_or_default();
    if target.trim().is_empty() || replacement.trim().is_empty() {
        return None;
    }
    Some((target, replacement))
}

fn normalize_correction_phrases(text: &str) -> String {
    if text.trim().is_empty() {
        return text.to_string();
    }
    if let Some(captures) = REPLACE_CORRECTION.captures(text) {
        let from = captures
            .get(1)
            .map(|value| value.as_str().trim())
            .unwrap_or("");
        let corrected_to = captures
            .get(3)
            .map(|value| value.as_str().trim().trim_end_matches(['.', '!']))
            .unwrap_or("");
        if !from.is_empty() && !corrected_to.is_empty() {
            return format!("replace {from} with {corrected_to}");
        }
    }
    if INSTEAD_OF_PHRASE.is_match(text) {
        return text.to_string();
    }
    if let Some(captures) = GENERAL_CORRECTION.captures(text) {
        let corrected_tail = captures
            .get(1)
            .map(|value| value.as_str().trim())
            .unwrap_or("");
        if !corrected_tail.is_empty() {
            return corrected_tail.to_string();
        }
    }
    text.to_string()
}

fn parse_deterministic_command(instruction: &str) -> Option<ParsedCommand> {
    let parsed: Vec<ParsedCommand> = [
        parse_no_op_command(instruction),
        parse_clear_all_command(instruction),
        parse_delete_command(instruction),
        parse_replace_command(instruction),
        parse_update_number_command(instruction),
    ]
    .into_iter()
    .flatten()
    .collect();
    if parsed.len() == 1 {
        parsed.into_iter().next()
    } else {
        None
    }
}

fn parse_no_op_command(instruction: &str) -> Option<ParsedCommand> {
    NO_OP.is_match(instruction).then_some(ParsedCommand {
        kind: CommandKind::NoOp,
        scope: CommandScope::All,
        target: None,
        replacement: None,
    })
}

fn parse_clear_all_command(instruction: &str) -> Option<ParsedCommand> {
    parse_delete_verb_command(instruction).filter(|command| command.kind == CommandKind::ClearAll)
}

fn parse_delete_command(instruction: &str) -> Option<ParsedCommand> {
    parse_delete_verb_command(instruction).filter(|command| command.kind == CommandKind::DeleteTerm)
}

fn parse_delete_verb_command(instruction: &str) -> Option<ParsedCommand> {
    for verb in DELETE_VERB_SPECS {
        let regex = Regex::new(&format!(
            r"(?i)^\s*(?:please\s+)?(?:{})(?:\s+(.+))?\s*$",
            verb.pattern
        ))
        .ok()?;
        let Some(captures) = regex.captures(instruction) else {
            continue;
        };
        let raw_target = captures
            .get(1)
            .map(|value| value.as_str().trim())
            .unwrap_or("");
        let supports_all = !verb
            .restrictions
            .contains(&DeleteVerbRestriction::TargetedOnly);
        let supports_targeted = !verb.restrictions.contains(&DeleteVerbRestriction::AllOnly);
        if raw_target.is_empty() {
            if verb.bare_means_all && supports_all {
                return Some(ParsedCommand {
                    kind: CommandKind::ClearAll,
                    scope: CommandScope::All,
                    target: None,
                    replacement: None,
                });
            }
            continue;
        }

        let scoped = scoped_target(raw_target)?;
        let target = normalize_command_term(&scoped.target, true);
        if target.is_empty() {
            return None;
        }
        if DELETE_ALL_TARGET.is_match(&target) {
            if supports_all && scoped.scope == CommandScope::All {
                return Some(ParsedCommand {
                    kind: CommandKind::ClearAll,
                    scope: CommandScope::All,
                    target: None,
                    replacement: None,
                });
            }
            return None;
        }
        if !supports_targeted || is_ambiguous_pronoun_target(&target) {
            return None;
        }
        return Some(ParsedCommand {
            kind: CommandKind::DeleteTerm,
            scope: scoped.scope,
            target: Some(target),
            replacement: None,
        });
    }
    None
}

fn parse_replace_command(instruction: &str) -> Option<ParsedCommand> {
    parse_replace_verb_command(instruction).or_else(|| parse_use_instead_command(instruction))
}

fn parse_use_instead_command(instruction: &str) -> Option<ParsedCommand> {
    let captures = REPLACE_USE_INSTEAD.captures(instruction)?;
    let from_scoped = scoped_target(captures.get(2)?.as_str())?;
    let from = normalize_command_term(&from_scoped.target, true);
    let to = normalize_replacement_term(captures.get(1)?.as_str());
    if from.is_empty() || to.is_empty() || is_ambiguous_pronoun_target(&from) {
        return None;
    }
    Some(ParsedCommand {
        kind: CommandKind::ReplaceTerm,
        scope: from_scoped.scope,
        target: Some(from),
        replacement: Some(to),
    })
}

fn parse_replace_verb_command(instruction: &str) -> Option<ParsedCommand> {
    for verb in REPLACE_VERB_SPECS {
        for connector in verb.connectors {
            let regex = Regex::new(&format!(
                r"(?i)^\s*(?:please\s+)?(?:{})\s+(.+?)\s+(?:{})\s+(.+?)\s*$",
                verb.pattern,
                connector.pattern()
            ))
            .ok()?;
            let Some(captures) = regex.captures(instruction) else {
                continue;
            };
            let from_scoped = scoped_target(captures.get(1)?.as_str())?;
            let from = normalize_command_term(&from_scoped.target, true);
            let to = normalize_replacement_term(captures.get(2)?.as_str());
            if from.is_empty() || to.is_empty() || is_ambiguous_pronoun_target(&from) {
                return None;
            }
            if verb
                .restrictions
                .contains(&ReplaceVerbRestriction::ExcludeNumberTarget)
                && NUMBER_WORD_TARGET.is_match(&from)
            {
                return None;
            }
            return Some(ParsedCommand {
                kind: CommandKind::ReplaceTerm,
                scope: from_scoped.scope,
                target: Some(from),
                replacement: Some(to),
            });
        }
    }
    None
}

fn parse_update_number_command(instruction: &str) -> Option<ParsedCommand> {
    let captures = UPDATE_NUMBER_COMMAND.captures(instruction)?;
    let replacement = normalize_replacement_term(captures.get(1)?.as_str());
    if replacement.is_empty() {
        return None;
    }
    Some(ParsedCommand {
        kind: CommandKind::UpdateNumber,
        scope: CommandScope::Last,
        target: None,
        replacement: Some(replacement),
    })
}

fn scoped_target(raw: &str) -> Option<ScopedTarget> {
    let mut target = raw.trim().to_string();
    target = DELETE_CONTEXT_SUFFIX.replace(&target, "").to_string();
    target = ARTICLE_WORD_PREFIX.replace(&target, "").to_string();
    target = target.trim().to_string();
    if target.is_empty() {
        return None;
    }

    let has_first = SCOPE_FIRST.is_match(&target);
    let has_last = SCOPE_LAST.is_match(&target);
    if has_first && has_last {
        return None;
    }
    let scope = if has_first {
        CommandScope::First
    } else if has_last {
        CommandScope::Last
    } else {
        CommandScope::All
    };
    target = SCOPED_PREFIX.replace(&target, "").to_string();
    target = SCOPED_SUFFIX.replace(&target, "").to_string();
    target = target.trim().to_string();
    (!target.is_empty()).then_some(ScopedTarget { scope, target })
}

fn apply_scoped_edit(
    source_text: &str,
    target: &str,
    replacement: &str,
    scope: CommandScope,
) -> ReplaceApplyResult {
    let matches = find_target_matches(source_text, target);
    if matches.is_empty() {
        return ReplaceApplyResult {
            output: source_text.to_string(),
            matched_count: 0,
        };
    }
    match scope {
        CommandScope::All => ReplaceApplyResult {
            output: replace_target_matches(source_text, target, |matched| {
                apply_replacement_casing(matched, replacement)
            }),
            matched_count: matches.len(),
        },
        CommandScope::First => {
            let first = matches.first().unwrap().clone();
            ReplaceApplyResult {
                output: replace_range(
                    source_text,
                    first.clone(),
                    &apply_replacement_casing(&source_text[first], replacement),
                ),
                matched_count: 1,
            }
        }
        CommandScope::Last => {
            let last = matches.last().unwrap().clone();
            ReplaceApplyResult {
                output: replace_range(
                    source_text,
                    last.clone(),
                    &apply_replacement_casing(&source_text[last], replacement),
                ),
                matched_count: 1,
            }
        }
    }
}

fn split_delete_targets(target: &str) -> Vec<String> {
    let normalized = target.trim();
    if !DELETE_TARGET_SEPARATOR.is_match(normalized) {
        return vec![normalized.to_string()];
    }
    let mut tokens = Vec::new();
    for token in DELETE_TARGET_SEPARATOR.split(normalized) {
        let term = normalize_command_term(token, true);
        if !term.is_empty() {
            tokens.push(term);
        }
    }
    if tokens.len() < 2 {
        return vec![normalized.to_string()];
    }
    if tokens
        .iter()
        .any(|token| WORD.find_iter(token).count() > MAX_MULTI_TARGET_TERM_WORDS)
    {
        return vec![normalized.to_string()];
    }
    let mut distinct = Vec::new();
    for token in tokens {
        if !distinct
            .iter()
            .any(|existing: &String| existing.eq_ignore_ascii_case(&token))
        {
            distinct.push(token);
        }
    }
    distinct
}

fn find_target_matches(source_text: &str, target: &str) -> Vec<Range<usize>> {
    if target.is_empty() {
        return Vec::new();
    }
    let escaped = regex::escape(target);
    let pattern = if SINGLE_TOKEN.is_match(target) {
        format!(r"(?i)\b{escaped}\b")
    } else {
        format!(r"(?i){escaped}")
    };
    Regex::new(&pattern)
        .map(|regex| regex.find_iter(source_text).map(|m| m.range()).collect())
        .unwrap_or_default()
}

fn replace_target_matches<F>(source_text: &str, target: &str, replacement_for: F) -> String
where
    F: Fn(&str) -> String,
{
    let matches = find_target_matches(source_text, target);
    if matches.is_empty() {
        return source_text.to_string();
    }
    let mut output = String::with_capacity(source_text.len());
    let mut cursor = 0usize;
    for range in matches {
        output.push_str(&source_text[cursor..range.start]);
        output.push_str(&replacement_for(&source_text[range.clone()]));
        cursor = range.end;
    }
    output.push_str(&source_text[cursor..]);
    output
}

fn apply_last_numeric_edit(source_text: &str, replacement: &str) -> ReplaceApplyResult {
    let matches: Vec<_> = NUMERIC_LIKE.find_iter(source_text).collect();
    if matches.is_empty() {
        return ReplaceApplyResult {
            output: source_text.to_string(),
            matched_count: 0,
        };
    }
    let last = matches.last().unwrap().range();
    ReplaceApplyResult {
        output: replace_range(source_text, last, replacement),
        matched_count: 1,
    }
}

fn replace_range(source_text: &str, range: Range<usize>, replacement: &str) -> String {
    let mut output = String::with_capacity(source_text.len() + replacement.len());
    output.push_str(&source_text[..range.start]);
    output.push_str(replacement);
    output.push_str(&source_text[range.end..]);
    output
}

fn apply_replacement_casing(source_match: &str, replacement: &str) -> String {
    if replacement.is_empty() || !is_capitalized_word_match(source_match) {
        return replacement.to_string();
    }
    let mut output = String::with_capacity(replacement.len());
    let mut changed = false;
    for current in replacement.chars() {
        if !changed && current.is_alphabetic() {
            output.extend(current.to_uppercase());
            changed = true;
        } else {
            output.push(current);
        }
    }
    output
}

fn is_capitalized_word_match(value: &str) -> bool {
    value
        .chars()
        .find(|current| current.is_alphabetic())
        .is_some_and(|current| current.is_uppercase())
}

fn passes_command_gate(normalized_instruction: &str) -> bool {
    normalized_instruction.len() <= MAX_COMMAND_CHARS
        && WORD.find_iter(normalized_instruction).count() <= MAX_COMMAND_WORDS
}

fn normalize_command_term(raw: &str, strip_article_word_prefix: bool) -> String {
    let mut term = raw.trim().to_string();
    term = TRIM_POLITE_SUFFIX.replace(&term, "").to_string();
    term = strip_wrapping_quotes(&term);
    if strip_article_word_prefix {
        term = ARTICLE_WORD_PREFIX.replace(&term, "").to_string();
    }
    term.trim()
        .trim_end_matches(['.', ',', ';', '!', '?', ':'])
        .trim()
        .to_string()
}

fn normalize_replacement_term(raw: &str) -> String {
    let mut term = raw.trim().to_string();
    term = TRIM_POLITE_SUFFIX.replace(&term, "").to_string();
    term = strip_wrapping_quotes(&term);
    term = ARTICLE_WORD_PREFIX.replace(&term, "").to_string();
    term.trim()
        .trim_end_matches(['.', ',', ';', '!', '?', ':'])
        .trim()
        .to_string()
}

fn strip_command_preamble(text: &str) -> String {
    let without_preamble = COMMAND_PREAMBLE
        .replace(text, "")
        .trim()
        .trim_end_matches('?')
        .trim()
        .to_string();
    if without_preamble.is_empty() {
        text.trim().to_string()
    } else {
        without_preamble
    }
}

fn is_ambiguous_pronoun_target(target: &str) -> bool {
    AMBIGUOUS_PRONOUN_TARGET.is_match(target.trim())
}

fn strip_wrapping_quotes(text: &str) -> String {
    let value = text.trim();
    if value.len() < 2 {
        return value.to_string();
    }
    let pairs = [('"', '"'), ('\'', '\''), ('“', '”'), ('‘', '’'), ('`', '`')];
    for (start, end) in pairs {
        if value.starts_with(start) && value.ends_with(end) {
            let start_index = start.len_utf8();
            let end_index = value.len() - end.len_utf8();
            return value[start_index..end_index].trim().to_string();
        }
    }
    value.to_string()
}

fn cleanup_edited_text(text: &str) -> String {
    if text.trim().is_empty() {
        return String::new();
    }
    MULTI_NEWLINE
        .replace_all(
            &SPACED_NEWLINE.replace_all(
                &MULTI_HORIZONTAL_SPACE
                    .replace_all(&SPACE_BEFORE_PUNCTUATION.replace_all(text, "$1"), " "),
                "\n",
            ),
            "\n\n",
        )
        .trim()
        .to_string()
}

fn apply_pre_rule(
    current: &mut String,
    rule_id: &'static str,
    rule: fn(&str) -> String,
    applied_rules: &mut Vec<&'static str>,
) {
    let updated = rule(current);
    if updated != *current {
        applied_rules.push(rule_id);
        *current = updated;
    }
}

fn remove_standalone_fillers(text: &str) -> String {
    FILLER.replace_all(text, " ").to_string()
}

fn collapse_adjacent_duplicates(text: &str) -> String {
    let mut current = text.to_string();
    loop {
        let updated = collapse_adjacent_duplicates_once(&current);
        if updated == current {
            return updated;
        }
        current = updated;
    }
}

fn collapse_adjacent_duplicates_once(text: &str) -> String {
    let tokens: Vec<_> = WORD_TOKEN.find_iter(text).collect();
    if tokens.len() < 2 {
        return text.to_string();
    }

    let mut remove_ranges = Vec::new();
    let mut previous_index = 0usize;
    for current_index in 1..tokens.len() {
        let previous = tokens[previous_index];
        let current = tokens[current_index];
        if text[previous.end()..current.start()]
            .chars()
            .all(char::is_whitespace)
            && previous.as_str().eq_ignore_ascii_case(current.as_str())
        {
            remove_ranges.push(previous.end()..current.end());
        } else {
            previous_index = current_index;
        }
    }

    if remove_ranges.is_empty() {
        return text.to_string();
    }

    let mut output = String::with_capacity(text.len());
    let mut cursor = 0usize;
    for range in remove_ranges {
        output.push_str(&text[cursor..range.start]);
        cursor = range.end;
    }
    output.push_str(&text[cursor..]);
    output
}

fn normalize_minutes(text: &str) -> String {
    MINUTES.replace_all(text, "minutes").to_string()
}

fn resolve_correction_turns(text: &str) -> String {
    let mut current = text.to_string();
    loop {
        let mut changed = false;
        let preposition_resolved = PREPOSITION_CORRECTION
            .replace_all(&current, |captures: &Captures| {
                let preposition = captures.get(1).unwrap().as_str();
                let repeated_preposition = captures.get(3).map(|value| value.as_str());
                if let Some(repeated) = repeated_preposition {
                    if !repeated.eq_ignore_ascii_case(preposition) {
                        return captures.get(0).unwrap().as_str().to_string();
                    }
                }
                changed = true;
                format!("{preposition} {}", captures.get(4).unwrap().as_str())
            })
            .to_string();
        current = preposition_resolved;

        let generic_resolved = GENERIC_CORRECTION
            .replace_all(&current, |captures: &Captures| {
                let old_value = captures.get(1).unwrap().as_str();
                let replacement = captures.get(2).unwrap().as_str();
                let trailing = captures.get(3).map(|value| value.as_str()).unwrap_or("");
                if !is_likely_correction_value(old_value, replacement) {
                    return captures.get(0).unwrap().as_str().to_string();
                }
                changed = true;
                format!("{replacement}{trailing}")
            })
            .to_string();
        current = generic_resolved;

        if !changed {
            return current;
        }
    }
}

fn is_likely_correction_value(old_value: &str, replacement: &str) -> bool {
    if old_value.eq_ignore_ascii_case(replacement) {
        return false;
    }
    let old_trimmed = old_value.trim();
    let replacement_trimmed = replacement.trim();
    if old_trimmed.is_empty() || replacement_trimmed.is_empty() {
        return false;
    }
    if old_trimmed.len() > 36 || replacement_trimmed.len() > 36 {
        return false;
    }
    if DIGIT.is_match(old_trimmed) || DIGIT.is_match(replacement_trimmed) {
        return true;
    }
    if contains_cardinal_word(old_trimmed) || contains_cardinal_word(replacement_trimmed) {
        return true;
    }
    old_trimmed.split_whitespace().count() <= 2
        && replacement_trimmed.split_whitespace().count() <= 2
}

fn contains_cardinal_word(text: &str) -> bool {
    text.to_lowercase()
        .replace('-', " ")
        .split_whitespace()
        .any(is_number_word)
}

fn number_words_to_digits(text: &str) -> String {
    NUMBER_SEQUENCE
        .replace_all(text, |captures: &Captures| {
            let value = captures.get(0).unwrap().as_str();
            parse_number_phrase(value)
                .map(|number| number.to_string())
                .unwrap_or_else(|| value.to_string())
        })
        .to_string()
}

fn parse_number_phrase(phrase: &str) -> Option<i64> {
    let tokens: Vec<String> = phrase
        .to_lowercase()
        .replace('-', " ")
        .split_whitespace()
        .filter(|token| !token.is_empty())
        .map(str::to_string)
        .collect();
    if tokens.is_empty() {
        return None;
    }
    if tokens
        .iter()
        .any(|token| !is_number_word(token) && token != "and")
    {
        return None;
    }

    if tokens.len() >= 2 && tokens.iter().all(|token| digit_word(token).is_some()) {
        let digits = tokens
            .iter()
            .map(|token| digit_word(token).unwrap().to_string())
            .collect::<Vec<String>>()
            .join("");
        return digits.parse::<i64>().ok();
    }

    let mut total = 0i64;
    let mut current = 0i64;
    let mut consumed = false;
    for token in tokens {
        if token == "and" {
            continue;
        } else if let Some(value) = digit_word(&token) {
            current += value;
            consumed = true;
        } else if let Some(value) = teen_word(&token) {
            current += value;
            consumed = true;
        } else if let Some(value) = tens_word(&token) {
            current += value;
            consumed = true;
        } else if token == "hundred" {
            current = if current == 0 { 1 } else { current } * 100;
            consumed = true;
        } else if token == "thousand" {
            let block = if current == 0 { 1 } else { current };
            total += block * 1000;
            current = 0;
            consumed = true;
        } else {
            return None;
        }
    }
    consumed.then_some(total + current)
}

fn surface_cleanup(text: &str) -> String {
    MULTI_SPACE
        .replace_all(
            &ORPHAN_COMMA_END.replace_all(
                &ORPHAN_COMMA_BEFORE_PUNCTUATION.replace_all(
                    &DUPLICATE_COMMA
                        .replace_all(&SPACE_BEFORE_PUNCTUATION.replace_all(text, "$1"), ","),
                    "$1",
                ),
                "",
            ),
            " ",
        )
        .trim()
        .to_string()
}

fn remove_surrounding_pair(text: &str, start: char, end: char) -> String {
    let trimmed = text.trim();
    if trimmed.len() >= 2 && trimmed.starts_with(start) && trimmed.ends_with(end) {
        trimmed[start.len_utf8()..trimmed.len() - end.len_utf8()]
            .trim()
            .to_string()
    } else {
        trimmed.to_string()
    }
}

fn collapse_repeated_fillers(text: &str) -> String {
    let mut output = Vec::new();
    let mut previous_filler: Option<String> = None;
    for token in text.split_whitespace() {
        let normalized = token.to_lowercase();
        if is_filler_token(&normalized) && previous_filler.as_deref() == Some(normalized.as_str()) {
            continue;
        }
        previous_filler = is_filler_token(&normalized).then_some(normalized);
        output.push(token);
    }
    output.join(" ")
}

fn collapse_repeated_punctuation(text: &str) -> String {
    let mut output = String::with_capacity(text.len());
    let mut previous: Option<char> = None;
    for current in text.chars() {
        if matches!(current, ',' | '.' | ';' | '!' | '?') && previous == Some(current) {
            continue;
        }
        output.push(current);
        previous = Some(current);
    }
    output
}

fn is_filler_token(token: &str) -> bool {
    FILLER_TOKEN.is_match(token)
}

fn sentence_capitalize(text: &str) -> String {
    if text.is_empty() {
        return text.to_string();
    }

    let mut chars: Vec<char> = text.chars().collect();
    let mut uppercase_next_letter = true;
    for index in 0..chars.len() {
        let current = chars[index];
        if uppercase_next_letter && current.is_alphabetic() {
            chars[index] = current.to_uppercase().next().unwrap_or(current);
            uppercase_next_letter = false;
        }
        if current.is_alphanumeric() {
            uppercase_next_letter = false;
        }
        if is_sentence_boundary(&chars, index) {
            uppercase_next_letter = true;
        }
    }
    let sentence_cased: String = chars.into_iter().collect();
    I_CONTRACTION
        .replace_all(
            &STANDALONE_I.replace_all(&sentence_cased, "I"),
            |captures: &Captures| format!("I'{}", captures.get(1).unwrap().as_str().to_lowercase()),
        )
        .to_string()
}

fn is_sentence_boundary(chars: &[char], index: usize) -> bool {
    let current = chars[index];
    if current == '\n' || current == '!' || current == '?' {
        return true;
    }
    if current != '.' {
        return false;
    }
    let previous = index.checked_sub(1).and_then(|i| chars.get(i));
    let next = chars.get(index + 1);
    if previous.is_some_and(|value| value.is_ascii_digit())
        && next.is_some_and(|value| value.is_ascii_digit())
    {
        return false;
    }
    next.is_none_or(|value| value.is_whitespace())
}

fn spoken_numbers_to_digits(text: &str) -> String {
    SPOKEN_NUMBER_SEQUENCE
        .replace_all(text, |captures: &Captures| {
            let value = captures.get(0).unwrap().as_str();
            spoken_number_to_digits(value)
                .map(|number| number.to_string())
                .unwrap_or_else(|| value.to_string())
        })
        .to_string()
}

fn spoken_number_to_digits(text: &str) -> Option<i64> {
    let words: Vec<String> = NUMBER_SEPARATOR
        .replace_all(&text.to_lowercase(), " ")
        .split_whitespace()
        .map(str::trim)
        .filter(|word| !word.is_empty() && *word != "and")
        .map(str::to_string)
        .collect();
    if words.is_empty() || words.len() == 1 || words.iter().any(|word| !is_spoken_number_word(word))
    {
        return None;
    }
    if words.iter().all(|word| digit_word(word).is_some()) {
        let digits = words
            .iter()
            .map(|word| digit_word(word).unwrap().to_string())
            .collect::<Vec<String>>()
            .join("");
        return digits.parse::<i64>().ok();
    }
    parse_cardinal_number(&words)
}

fn parse_cardinal_number(words: &[String]) -> Option<i64> {
    parse_scaled_cardinal(words, "million", 1_000_000)
        .or_else(|| parse_scaled_cardinal(words, "thousand", 1_000))
        .or_else(|| parse_under_thousand(words))
}

fn parse_scaled_cardinal(words: &[String], scale_word: &str, scale_value: i64) -> Option<i64> {
    let scale_positions: Vec<usize> = words
        .iter()
        .enumerate()
        .filter_map(|(index, word)| (word == scale_word).then_some(index))
        .collect();
    if scale_positions.len() != 1 || scale_positions[0] == 0 {
        return None;
    }
    let scale_index = scale_positions[0];
    let prefix = parse_under_thousand(&words[..scale_index])?;
    if prefix == 0 {
        return None;
    }
    let suffix_words = &words[scale_index + 1..];
    let suffix = if suffix_words.is_empty() {
        0
    } else {
        parse_cardinal_number(suffix_words)?
    };
    Some(prefix * scale_value + suffix)
}

fn parse_under_thousand(words: &[String]) -> Option<i64> {
    if words.is_empty() {
        return None;
    }
    if let Some(hundred_index) = words.iter().position(|word| word == "hundred") {
        if hundred_index != 1
            || words
                .iter()
                .filter(|word| word.as_str() == "hundred")
                .count()
                != 1
        {
            return None;
        }
        let hundreds = digit_word(words.first()?)?;
        if hundreds == 0 {
            return None;
        }
        let remainder_words = &words[2..];
        let remainder = if remainder_words.is_empty() {
            0
        } else {
            parse_under_hundred(remainder_words)?
        };
        return Some(hundreds * 100 + remainder);
    }
    parse_under_hundred(words)
}

fn parse_under_hundred(words: &[String]) -> Option<i64> {
    match words.len() {
        1 => digit_word(&words[0])
            .or_else(|| teen_word(&words[0]))
            .or_else(|| tens_word(&words[0])),
        2 => {
            let tens = tens_word(&words[0])?;
            let ones = digit_word(&words[1])?;
            (ones != 0).then_some(tens + ones)
        }
        _ => None,
    }
}

fn choose_guarded_output(original: &str, candidate: &str) -> String {
    if original.is_empty() {
        return candidate.to_string();
    }
    if candidate.is_empty() {
        return original.to_string();
    }
    if is_excessive_length_shift(original, candidate)
        || looks_like_assistant_reply(original, candidate)
        || is_low_token_overlap(original, candidate)
    {
        return original.to_string();
    }
    candidate.to_string()
}

fn is_excessive_length_shift(original: &str, candidate: &str) -> bool {
    let original_chars = original.chars().count() as f64;
    let candidate_chars = candidate.chars().count() as f64;
    let expanded_too_much =
        candidate_chars > original_chars * 1.5 && candidate_chars - original_chars > 20.0;
    if expanded_too_much {
        return true;
    }
    candidate_chars < original_chars * 0.5 && original_chars - candidate_chars > 20.0
}

fn looks_like_assistant_reply(original: &str, candidate: &str) -> bool {
    let candidate_lower = candidate.to_lowercase();
    if !ASSISTANT_REPLY_PREFIXES
        .iter()
        .any(|prefix| candidate_lower.starts_with(prefix))
    {
        return false;
    }
    let original_lower = original.to_lowercase();
    !ASSISTANT_REPLY_PREFIXES
        .iter()
        .any(|prefix| original_lower.starts_with(prefix))
}

fn is_low_token_overlap(original: &str, candidate: &str) -> bool {
    let original_tokens: Vec<String> = WORD_TOKEN
        .find_iter(&original.to_lowercase())
        .map(|token| token.as_str().to_string())
        .collect();
    let candidate_tokens: Vec<String> = WORD_TOKEN
        .find_iter(&candidate.to_lowercase())
        .map(|token| token.as_str().to_string())
        .collect();
    if original_tokens.len() < 4 || candidate_tokens.len() < 4 {
        return false;
    }
    let original_set: std::collections::HashSet<&String> = original_tokens.iter().collect();
    let overlap_count = candidate_tokens
        .iter()
        .filter(|token| original_set.contains(token))
        .count();
    (overlap_count as f64 / candidate_tokens.len() as f64) < 0.55
}

fn is_number_word(word: &str) -> bool {
    digit_word(word).is_some()
        || teen_word(word).is_some()
        || tens_word(word).is_some()
        || matches!(word, "hundred" | "thousand")
}

fn is_spoken_number_word(word: &str) -> bool {
    is_number_word(word) || word == "million"
}

fn digit_word(word: &str) -> Option<i64> {
    match word {
        "zero" => Some(0),
        "one" => Some(1),
        "two" => Some(2),
        "three" => Some(3),
        "four" => Some(4),
        "five" => Some(5),
        "six" => Some(6),
        "seven" => Some(7),
        "eight" => Some(8),
        "nine" => Some(9),
        _ => None,
    }
}

fn teen_word(word: &str) -> Option<i64> {
    match word {
        "ten" => Some(10),
        "eleven" => Some(11),
        "twelve" => Some(12),
        "thirteen" => Some(13),
        "fourteen" => Some(14),
        "fifteen" => Some(15),
        "sixteen" => Some(16),
        "seventeen" => Some(17),
        "eighteen" => Some(18),
        "nineteen" => Some(19),
        _ => None,
    }
}

fn tens_word(word: &str) -> Option<i64> {
    match word {
        "twenty" => Some(20),
        "thirty" => Some(30),
        "forty" => Some(40),
        "fifty" => Some(50),
        "sixty" => Some(60),
        "seventy" => Some(70),
        "eighty" => Some(80),
        "ninety" => Some(90),
        _ => None,
    }
}

fn jni_string_to_rust(env: &mut JNIEnv, input: &JString) -> String {
    env.get_string(&input)
        .map(|value| value.to_string_lossy().into_owned())
        .unwrap_or_default()
}

fn rust_string_to_jni(env: &mut JNIEnv, output: String) -> jstring {
    env.new_string(output)
        .expect("failed to allocate JNI string")
        .into_raw()
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativePreprocessText(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jstring {
    let text = jni_string_to_rust(&mut env, &input);
    rust_string_to_jni(&mut env, preprocess(&text).text)
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativePreprocessRuleIds(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jstring {
    let text = jni_string_to_rust(&mut env, &input);
    let result = preprocess(&text).applied_rules.join("|");
    rust_string_to_jni(&mut env, result)
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeNormalizeComposeInput(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jstring {
    let text = jni_string_to_rust(&mut env, &input);
    rust_string_to_jni(&mut env, normalize_compose_input(&text))
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeNormalizeInstructionInput(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jstring {
    let text = jni_string_to_rust(&mut env, &input);
    rust_string_to_jni(&mut env, normalize_instruction_input(&text))
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeCleanModelOutput(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
    bullet_mode: jboolean,
) -> jstring {
    let text = jni_string_to_rust(&mut env, &input);
    rust_string_to_jni(&mut env, clean_model_output(&text, bullet_mode != 0))
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeNormalizeComposeOutputText(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jstring {
    let text = jni_string_to_rust(&mut env, &input);
    rust_string_to_jni(&mut env, normalize_compose_output_text(&text))
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeFinalizeComposeOutput(
    mut env: JNIEnv,
    _class: JClass,
    original_text: JString,
    model_output: JString,
    list_mode: jboolean,
) -> jstring {
    let original = jni_string_to_rust(&mut env, &original_text);
    let output = jni_string_to_rust(&mut env, &model_output);
    rust_string_to_jni(&mut env, postprocess(&original, &output, list_mode != 0))
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeAnalyzeInstruction(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jstring {
    let text = jni_string_to_rust(&mut env, &input);
    let analysis = analyze_instruction(&text);
    rust_string_to_jni(
        &mut env,
        format!(
            "{}{FIELD_SEPARATOR}{}",
            sanitize_field(&analysis.normalized_instruction),
            analysis.intent.as_str()
        ),
    )
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeIsStrictEditCommand(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jboolean {
    let text = jni_string_to_rust(&mut env, &input);
    if is_strict_edit_command(&text) {
        1
    } else {
        0
    }
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeTryApplyDeterministicEdit(
    mut env: JNIEnv,
    _class: JClass,
    source_text: JString,
    instruction_text: JString,
) -> jstring {
    let source = jni_string_to_rust(&mut env, &source_text);
    let instruction = jni_string_to_rust(&mut env, &instruction_text);
    let encoded = try_apply_deterministic_edit(&source, &instruction)
        .map(|result| {
            format!(
                "{}{FIELD_SEPARATOR}{}{FIELD_SEPARATOR}{}{FIELD_SEPARATOR}{}{FIELD_SEPARATOR}{}{FIELD_SEPARATOR}{}{FIELD_SEPARATOR}{}{FIELD_SEPARATOR}{}",
                sanitize_field(&result.output),
                result.applied,
                result.intent.as_str(),
                result.scope.as_str(),
                result.command_kind.as_str(),
                result.matched_count,
                result.rule_confidence.as_str(),
                result.no_match_detected
            )
        })
        .unwrap_or_default();
    rust_string_to_jni(&mut env, encoded)
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativeLooksLikeList(
    mut env: JNIEnv,
    _class: JClass,
    input: JString,
) -> jboolean {
    let text = jni_string_to_rust(&mut env, &input);
    if looks_like_list(&text) {
        1
    } else {
        0
    }
}

#[no_mangle]
pub extern "system" fn Java_com_sanogueralorenzo_voice_engine_NativeVoiceEngine_nativePostReplaceCapitalization(
    mut env: JNIEnv,
    _class: JClass,
    source_text: JString,
    instruction_text: JString,
    edited_output: JString,
) -> jstring {
    let source = jni_string_to_rust(&mut env, &source_text);
    let instruction = jni_string_to_rust(&mut env, &instruction_text);
    let output = jni_string_to_rust(&mut env, &edited_output);
    rust_string_to_jni(
        &mut env,
        post_replace_capitalization(&source, &instruction, &output),
    )
}

fn sanitize_field(value: &str) -> String {
    value.replace(FIELD_SEPARATOR, " ")
}

static FILLER: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"(?i)\b(?:um+|uh+|uhh+|erm+|emm+|hmm+)\b").unwrap());
static WORD_TOKEN: Lazy<Regex> = Lazy::new(|| Regex::new(r"\b[\p{L}\p{N}']+\b").unwrap());
static MINUTES: Lazy<Regex> = Lazy::new(|| Regex::new(r"(?i)\bmins?\b").unwrap());
static WHITESPACE: Lazy<Regex> = Lazy::new(|| Regex::new(r"\s+").unwrap());
static DIGIT: Lazy<Regex> = Lazy::new(|| Regex::new(r"\d").unwrap());
static PREPOSITION_CORRECTION: Lazy<Regex> = Lazy::new(|| {
    Regex::new(
        r"(?i)\b(to|at|on|for|in|after|before|around|about)\s+([\p{L}\p{N}:.'-]+(?:\s+[\p{L}\p{N}:.'-]+){0,3})\s*(?:,\s*)?(?:no|actually|sorry|rather|instead|i\s+mean)\s+(?:(to|at|on|for|in|after|before|around|about)\s+)?([\p{L}\p{N}:.'-]+(?:\s+[\p{L}\p{N}:.'-]+){0,3})",
    )
    .unwrap()
});
static GENERIC_CORRECTION: Lazy<Regex> = Lazy::new(|| {
    Regex::new(
        r"(?i)\b([\p{L}\p{N}:.'-]+(?:\s+[\p{L}\p{N}:.'-]+){0,2})\s*(?:,\s*)?(?:no|actually|sorry|rather|instead|i\s+mean)\s+([\p{L}\p{N}:.'-]+(?:\s+[\p{L}\p{N}:.'-]+){0,2})(\s*[.!?,;:]|$)",
    )
    .unwrap()
});
static NUMBER_SEQUENCE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand)(?:[\s-]+(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|and))*\b").unwrap()
});
static SPACE_BEFORE_PUNCTUATION: Lazy<Regex> = Lazy::new(|| Regex::new(r"\s+([,.;!?])").unwrap());
static DUPLICATE_COMMA: Lazy<Regex> = Lazy::new(|| Regex::new(r",\s*,+").unwrap());
static ORPHAN_COMMA_BEFORE_PUNCTUATION: Lazy<Regex> =
    Lazy::new(|| Regex::new(r",\s*([.!?])").unwrap());
static ORPHAN_COMMA_END: Lazy<Regex> = Lazy::new(|| Regex::new(r",\s*$").unwrap());
static MULTI_SPACE: Lazy<Regex> = Lazy::new(|| Regex::new(r" {2,}").unwrap());
static FILLER_TOKEN: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"(?i)^(?:um+|uh+|erm+|emm+|hmm+)$").unwrap());
static CLEANED_ANCHOR: Lazy<Regex> = Lazy::new(|| Regex::new(r"(?im)^cleaned\s*:\s*").unwrap());
static PREFIX_LABEL: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"(?i)^(rewritten|rewrite|cleaned|output|result)\s*:\s*").unwrap());
static STANDALONE_I: Lazy<Regex> = Lazy::new(|| Regex::new(r"(?i)\bi\b").unwrap());
static I_CONTRACTION: Lazy<Regex> = Lazy::new(|| Regex::new(r"(?i)\bi'([a-z]+)\b").unwrap());
static NUMBER_SEPARATOR: Lazy<Regex> = Lazy::new(|| Regex::new(r"[,\-]").unwrap());
static SPOKEN_NUMBER_SEQUENCE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)\b(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million)(?:(?:\s*,\s*|\s+|-)(?:and\s+)?(?:zero|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve|thirteen|fourteen|fifteen|sixteen|seventeen|eighteen|nineteen|twenty|thirty|forty|fifty|sixty|seventy|eighty|ninety|hundred|thousand|million))*\b").unwrap()
});
static ASSISTANT_REPLY_PREFIXES: &[&str] =
    &["sure", "yes", "no problem", "absolutely", "i can", "here"];
const FIELD_SEPARATOR: char = '\u{1F}';

const MAX_COMMAND_WORDS: usize = 10;
const MAX_COMMAND_CHARS: usize = 96;
const MAX_MULTI_TARGET_TERM_WORDS: usize = 3;

const DELETE_VERB_SPECS: &[DeleteVerbSpec] = &[
    DeleteVerbSpec {
        pattern: r"get\s+rid\s+of",
        bare_means_all: false,
        restrictions: &[],
    },
    DeleteVerbSpec {
        pattern: r"take\s+out",
        bare_means_all: false,
        restrictions: &[],
    },
    DeleteVerbSpec {
        pattern: r"start\s+over",
        bare_means_all: true,
        restrictions: &[DeleteVerbRestriction::AllOnly],
    },
    DeleteVerbSpec {
        pattern: "delete",
        bare_means_all: false,
        restrictions: &[],
    },
    DeleteVerbSpec {
        pattern: "clear",
        bare_means_all: false,
        restrictions: &[],
    },
    DeleteVerbSpec {
        pattern: "erase",
        bare_means_all: false,
        restrictions: &[],
    },
    DeleteVerbSpec {
        pattern: "wipe",
        bare_means_all: false,
        restrictions: &[],
    },
    DeleteVerbSpec {
        pattern: "remove",
        bare_means_all: false,
        restrictions: &[],
    },
    DeleteVerbSpec {
        pattern: "reset",
        bare_means_all: true,
        restrictions: &[DeleteVerbRestriction::AllOnly],
    },
    DeleteVerbSpec {
        pattern: "undo",
        bare_means_all: true,
        restrictions: &[],
    },
    DeleteVerbSpec {
        pattern: "drop",
        bare_means_all: false,
        restrictions: &[DeleteVerbRestriction::TargetedOnly],
    },
    DeleteVerbSpec {
        pattern: "cut",
        bare_means_all: false,
        restrictions: &[],
    },
];

const REPLACE_VERB_SPECS: &[ReplaceVerbSpec] = &[
    ReplaceVerbSpec {
        pattern: "replace",
        connectors: &[ReplaceConnector::With],
        restrictions: &[],
    },
    ReplaceVerbSpec {
        pattern: "change",
        connectors: &[
            ReplaceConnector::To,
            ReplaceConnector::With,
            ReplaceConnector::For,
        ],
        restrictions: &[],
    },
    ReplaceVerbSpec {
        pattern: "swap",
        connectors: &[ReplaceConnector::For, ReplaceConnector::With],
        restrictions: &[],
    },
    ReplaceVerbSpec {
        pattern: "substitute",
        connectors: &[ReplaceConnector::With, ReplaceConnector::For],
        restrictions: &[],
    },
    ReplaceVerbSpec {
        pattern: "update",
        connectors: &[ReplaceConnector::To, ReplaceConnector::With],
        restrictions: &[ReplaceVerbRestriction::ExcludeNumberTarget],
    },
    ReplaceVerbSpec {
        pattern: "correct",
        connectors: &[ReplaceConnector::To, ReplaceConnector::With],
        restrictions: &[],
    },
    ReplaceVerbSpec {
        pattern: "fix",
        connectors: &[ReplaceConnector::To, ReplaceConnector::With],
        restrictions: &[],
    },
];

static WORD: Lazy<Regex> = Lazy::new(|| Regex::new(r"\p{L}[\p{L}\p{N}'’-]*").unwrap());
static COMMAND_PREAMBLE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(
        r"(?i)^\s*(?:(?:okay|ok|hey)\s+)?(?:(?:can|could|would|will)\s+you\s+)?(?:please\s+)?",
    )
    .unwrap()
});
static NO_OP: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)^\s*(?:(?:actually)\s+)?(?:(?:just)\s+)?(?:never\s*mind|cancel(?:\s+that)?|forget\s+it|ignore\s+that|disregard\s+that)\s*[.!]?\s*$").unwrap()
});
static REPLACE_USE_INSTEAD: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)^\s*(?:please\s+)?use\s+(.+?)\s+instead\s+of\s+(.+?)\s*$").unwrap()
});
static UPDATE_NUMBER_COMMAND: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)^\s*(?:please\s+)?update\s+number\s+(?:to|with)\s+(.+?)\s*$").unwrap()
});
static DELETE_TARGET_SEPARATOR: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"(?i)\s*(?:,|\band\b)\s*").unwrap());
static NUMERIC_LIKE: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"(?i)\b\d{1,4}(?::\d{2})?(?:\s?(?:am|pm))?\b").unwrap());
static DELETE_ALL_TARGET: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)^(?:all|everything|(?:the\s+)?(?:whole|entire)\s+(?:message|text)|(?:the\s+)?message|(?:the\s+)?text)$").unwrap()
});
static REPLACE_CORRECTION: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)^\s*(?:please\s+)?replace\s+(.+?)\s+with\s+(.+?)\s*(?:,?\s*(?:no|actually|instead|wait)\s*,?\s*(?:let'?s\s+do|make\s+it|use)?\s+(.+))\s*$").unwrap()
});
static GENERAL_CORRECTION: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)^\s*.+?\s+(?:no|actually|instead|rather|wait)\s*,?\s*(?:let'?s\s+do|make\s+it|use)?\s+(.+)\s*$").unwrap()
});
static INSTEAD_OF_PHRASE: Lazy<Regex> = Lazy::new(|| Regex::new(r"(?i)\binstead\s+of\b").unwrap());
static DELETE_CONTEXT_SUFFIX: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)\s+(?:from\s+(?:(?:my|the)\s+)?(?:shopping\s+)?list|from\s+(?:the\s+)?(?:message|text)|in\s+(?:the\s+)?(?:message|text)|from\s+it)$").unwrap()
});
static SCOPED_PREFIX: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"(?i)^(?:only\s+)?(?:first|last|final)\s+").unwrap());
static SCOPED_SUFFIX: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"(?i)\s+(?:only\s+first|first|last|final)$").unwrap());
static SCOPE_FIRST: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"(?i)\b(?:only\s+first|first)\b").unwrap());
static SCOPE_LAST: Lazy<Regex> = Lazy::new(|| Regex::new(r"(?i)\b(?:last|final)\b").unwrap());
static AMBIGUOUS_PRONOUN_TARGET: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"(?i)^(?:it|that|this|thing|part)$").unwrap());
static NUMBER_WORD_TARGET: Lazy<Regex> = Lazy::new(|| Regex::new(r"(?i)^number$").unwrap());
static EXPLICIT_BULLET: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"(?m)^\s*(?:[-*•]|\d+[.)])\s+\S+").unwrap());
static LIST_CUE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)\b(first|second|third|fourth|fifth|next|then|finally|list|bullet|bullets|items?|steps?|points?)\b|\d+[.)]").unwrap()
});
static SHOPPING_TASK_CUE: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)\b(buy|shopping|groceries|todo|to-do|tasks?|pick\s+up|get\s+me|remember\s+to|need\s+to)\b").unwrap()
});
static DELIMITED_ITEMS: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"\b\w+\b\s*[,;|]\s*\b\w+\b\s*[,;|]").unwrap());
static SINGLE_TOKEN: Lazy<Regex> = Lazy::new(|| Regex::new(r"^[\p{L}\p{N}_'’-]+$").unwrap());
static ARTICLE_WORD_PREFIX: Lazy<Regex> = Lazy::new(|| {
    Regex::new(r"(?i)^(?:(?:the|a|an)\s+)?(?:word|phrase|term|text|token)\s+").unwrap()
});
static TRIM_POLITE_SUFFIX: Lazy<Regex> =
    Lazy::new(|| Regex::new(r"(?i)\s*(?:please|pls|thanks|thank\s+you)$").unwrap());
static MULTI_HORIZONTAL_SPACE: Lazy<Regex> = Lazy::new(|| Regex::new(r"[ \t]{2,}").unwrap());
static SPACED_NEWLINE: Lazy<Regex> = Lazy::new(|| Regex::new(r"[ \t]*\n[ \t]*").unwrap());
static MULTI_NEWLINE: Lazy<Regex> = Lazy::new(|| Regex::new(r"\n{3,}").unwrap());

#[cfg(test)]
mod tests {
    use super::*;
    use serde::Deserialize;

    #[derive(Deserialize)]
    struct FixtureFile<T> {
        version: u32,
        operation: String,
        cases: Vec<T>,
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct PreprocessFixture {
        name: String,
        input: String,
        expected_text: String,
        expected_changed: bool,
        expected_applied_rule_ids: Vec<String>,
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct NormalizationFixtures {
        version: u32,
        operation: String,
        compose_input_cases: Vec<TextFixture>,
        instruction_input_cases: Vec<TextFixture>,
        compose_output_cases: Vec<TextFixture>,
        clean_model_output_cases: Vec<CleanModelOutputFixture>,
    }

    #[derive(Deserialize)]
    struct TextFixture {
        name: String,
        input: String,
        expected: String,
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct CleanModelOutputFixture {
        name: String,
        input: String,
        bullet_mode: bool,
        expected: String,
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct PostprocessFixture {
        name: String,
        original_text: String,
        model_output: String,
        list_mode: bool,
        expected: String,
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct EditAnalysisFixtures {
        version: u32,
        operation: String,
        cases: Vec<EditAnalysisFixture>,
        allow_blank_output_cases: Vec<AllowBlankOutputFixture>,
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct EditAnalysisFixture {
        name: String,
        instruction: String,
        expected_normalized_instruction: String,
        expected_intent: String,
        expected_strict_edit_command: bool,
    }

    #[derive(Deserialize)]
    struct AllowBlankOutputFixture {
        intent: String,
        expected: bool,
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct DeterministicEditFixtures {
        version: u32,
        operation: String,
        cases: Vec<DeterministicEditFixture>,
        null_cases: Vec<NullEditFixture>,
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct DeterministicEditFixture {
        name: String,
        source_text: String,
        instruction: String,
        expected: ExpectedDeterministicEdit,
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct ExpectedDeterministicEdit {
        output: String,
        applied: bool,
        intent: String,
        scope: String,
        command_kind: String,
        matched_count: usize,
        rule_confidence: String,
        no_match_detected: bool,
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct NullEditFixture {
        name: String,
        source_text: String,
        instruction: String,
    }

    #[derive(Deserialize)]
    struct BooleanFixture {
        name: String,
        input: String,
        expected: bool,
    }

    #[derive(Deserialize)]
    #[serde(rename_all = "camelCase")]
    struct ReplacementCasingFixture {
        name: String,
        source_text: String,
        instruction: String,
        edited_output: String,
        expected: String,
    }

    fn parse_fixture<T>(json: &str) -> FixtureFile<T>
    where
        T: for<'de> Deserialize<'de>,
    {
        let file: FixtureFile<T> = serde_json::from_str(json).expect("fixture json should parse");
        assert_eq!(1, file.version);
        file
    }

    fn parse_edit_intent(value: &str) -> EditIntent {
        match value {
            "GENERAL" => EditIntent::General,
            "DELETE_ALL" => EditIntent::DeleteAll,
            "REPLACE" => EditIntent::Replace,
            _ => panic!("unknown edit intent: {value}"),
        }
    }

    fn assert_deterministic_edit(
        case_name: &str,
        actual: DeterministicEditResult,
        expected: ExpectedDeterministicEdit,
    ) {
        assert_eq!(expected.output, actual.output, "{case_name}");
        assert_eq!(expected.applied, actual.applied, "{case_name}");
        assert_eq!(expected.intent, actual.intent.as_str(), "{case_name}");
        assert_eq!(expected.scope, actual.scope.as_str(), "{case_name}");
        assert_eq!(
            expected.command_kind,
            actual.command_kind.as_str(),
            "{case_name}"
        );
        assert_eq!(expected.matched_count, actual.matched_count, "{case_name}");
        assert_eq!(
            expected.rule_confidence,
            actual.rule_confidence.as_str(),
            "{case_name}"
        );
        assert_eq!(
            expected.no_match_detected, actual.no_match_detected,
            "{case_name}"
        );
    }

    #[test]
    fn preprocess_applies_rules_in_order() {
        let result = preprocess("um meet meet me in 5 mins");

        assert_eq!("meet me in 5 minutes", result.text);
        assert_eq!(
            vec!["FILLER", "ADJACENT_DUPLICATE", "MINUTES_NORMALIZATION"],
            result.applied_rules
        );
    }

    #[test]
    fn preprocess_applies_correction_before_number_conversion() {
        let result = preprocess("at five, no at six");

        assert_eq!("at 6", result.text);
        assert_eq!(
            vec!["CORRECTION_TURN", "NUMBER_WORDS_TO_DIGITS"],
            result.applied_rules
        );
    }

    #[test]
    fn clean_model_output_matches_spoken_number_guards() {
        assert_eq!(
            "The code is 123",
            clean_model_output("the code is one, two, three", false)
        );
        assert_eq!(
            "The code is one twenty three",
            clean_model_output("the code is one twenty three", false)
        );
        assert_eq!(
            "The code is twenty one five",
            clean_model_output("the code is twenty one five", false)
        );
    }

    #[test]
    fn postprocess_rejects_assistant_reply() {
        assert_eq!(
            "buy milk and bread",
            postprocess("buy milk and bread", "Sure, buy milk and bread", false)
        );
    }

    #[test]
    fn conformance_preprocess_matches_fixtures() {
        let file: FixtureFile<PreprocessFixture> =
            parse_fixture(include_str!("../fixtures/preprocess.json"));
        assert_eq!("preprocess", file.operation);

        for case in file.cases {
            let result = preprocess(&case.input);
            assert_eq!(case.expected_text, result.text, "{}", case.name);
            assert_eq!(case.expected_changed, result.changed, "{}", case.name);
            assert_eq!(
                case.expected_applied_rule_ids, result.applied_rules,
                "{}",
                case.name
            );
        }
    }

    #[test]
    fn conformance_normalization_matches_fixtures() {
        let file: NormalizationFixtures =
            serde_json::from_str(include_str!("../fixtures/normalization.json"))
                .expect("normalization fixture json should parse");
        assert_eq!(1, file.version);
        assert_eq!("normalization", file.operation);

        for case in file.compose_input_cases {
            assert_eq!(
                case.expected,
                normalize_compose_input(&case.input),
                "{}",
                case.name
            );
        }
        for case in file.instruction_input_cases {
            assert_eq!(
                case.expected,
                normalize_instruction_input(&case.input),
                "{}",
                case.name
            );
        }
        for case in file.compose_output_cases {
            assert_eq!(
                case.expected,
                normalize_compose_output_text(&case.input),
                "{}",
                case.name
            );
        }
        for case in file.clean_model_output_cases {
            assert_eq!(
                case.expected,
                clean_model_output(&case.input, case.bullet_mode),
                "{}",
                case.name
            );
        }
    }

    #[test]
    fn conformance_postprocess_matches_fixtures() {
        let file: FixtureFile<PostprocessFixture> =
            parse_fixture(include_str!("../fixtures/postprocess.json"));
        assert_eq!("postprocess", file.operation);

        for case in file.cases {
            assert_eq!(
                case.expected,
                postprocess(&case.original_text, &case.model_output, case.list_mode),
                "{}",
                case.name
            );
        }
    }

    #[test]
    fn conformance_edit_analysis_matches_fixtures() {
        let file: EditAnalysisFixtures =
            serde_json::from_str(include_str!("../fixtures/edit_analysis.json"))
                .expect("edit analysis fixture json should parse");
        assert_eq!(1, file.version);
        assert_eq!("edit_analysis", file.operation);

        for case in file.cases {
            let analysis = analyze_instruction(&case.instruction);
            assert_eq!(
                case.expected_normalized_instruction, analysis.normalized_instruction,
                "{}",
                case.name
            );
            assert_eq!(
                case.expected_intent,
                analysis.intent.as_str(),
                "{}",
                case.name
            );
            assert_eq!(
                case.expected_strict_edit_command,
                is_strict_edit_command(&case.instruction),
                "{}",
                case.name
            );
        }

        for case in file.allow_blank_output_cases {
            assert_eq!(
                case.expected,
                should_allow_blank_output(parse_edit_intent(&case.intent)),
                "{}",
                case.intent
            );
        }
    }

    #[test]
    fn conformance_deterministic_edits_match_fixtures() {
        let file: DeterministicEditFixtures =
            serde_json::from_str(include_str!("../fixtures/deterministic_edits.json"))
                .expect("deterministic edit fixture json should parse");
        assert_eq!(1, file.version);
        assert_eq!("deterministic_edits", file.operation);

        for case in file.cases {
            let actual = try_apply_deterministic_edit(&case.source_text, &case.instruction)
                .unwrap_or_else(|| panic!("expected deterministic edit result: {}", case.name));
            assert_deterministic_edit(&case.name, actual, case.expected);
        }

        for case in file.null_cases {
            assert!(
                try_apply_deterministic_edit(&case.source_text, &case.instruction).is_none(),
                "{}",
                case.name
            );
        }
    }

    #[test]
    fn conformance_list_detection_matches_fixtures() {
        let file: FixtureFile<BooleanFixture> =
            parse_fixture(include_str!("../fixtures/list_detection.json"));
        assert_eq!("list_detection", file.operation);

        for case in file.cases {
            assert_eq!(case.expected, looks_like_list(&case.input), "{}", case.name);
        }
    }

    #[test]
    fn conformance_replacement_casing_matches_fixtures() {
        let file: FixtureFile<ReplacementCasingFixture> =
            parse_fixture(include_str!("../fixtures/replacement_casing.json"));
        assert_eq!("replacement_casing", file.operation);

        for case in file.cases {
            assert_eq!(
                case.expected,
                post_replace_capitalization(
                    &case.source_text,
                    &case.instruction,
                    &case.edited_output
                ),
                "{}",
                case.name
            );
        }
    }

    #[test]
    fn contract_jni_text_fields_replace_field_separator() {
        assert_eq!(
            "hello world",
            sanitize_field(&format!("hello{FIELD_SEPARATOR}world"))
        );
    }
}
