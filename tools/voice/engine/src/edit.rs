use regex::Regex;
use std::ops::Range;

use super::*;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum EditIntent {
    General,
    DeleteAll,
    Replace,
}

impl EditIntent {
    pub(crate) fn as_str(self) -> &'static str {
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
}

impl CommandScope {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            CommandScope::All => "ALL",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CommandKind {
    ClearAll,
    DeleteTerm,
    ReplaceTerm,
}

impl CommandKind {
    pub(crate) fn as_str(self) -> &'static str {
        match self {
            CommandKind::ClearAll => "CLEAR_ALL",
            CommandKind::DeleteTerm => "DELETE_TERM",
            CommandKind::ReplaceTerm => "REPLACE_TERM",
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum RuleConfidence {
    High,
    Low,
}

impl RuleConfidence {
    pub(crate) fn as_str(self) -> &'static str {
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
    target: Option<String>,
    replacement: Option<String>,
}

struct ReplaceApplyResult {
    output: String,
    matched_count: usize,
}

pub fn analyze_instruction(instruction_text: &str) -> EditInstructionAnalysis {
    let collapsed = WHITESPACE
        .replace_all(instruction_text, " ")
        .trim()
        .to_string();
    let normalized = normalize_correction_phrases(&collapsed);
    let command_candidate = strip_command_preamble(&normalized);
    let clear_command = parse_clear_all_command(&command_candidate);
    let replace_command = parse_replace_command(&command_candidate);
    let intent = if clear_command.is_some() {
        EditIntent::DeleteAll
    } else if replace_command.is_some() {
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
    parse_clear_all_command(&command_candidate).is_some()
        || parse_delete_command(&command_candidate).is_some()
        || parse_replace_command(&command_candidate).is_some()
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
            let mut updated = source_text.to_string();
            let mut total_matched = 0usize;
            for term in targets {
                let replace_result = apply_edit(&updated, &term, "");
                updated = replace_result.output;
                total_matched += replace_result.matched_count;
            }
            let output = cleanup_edited_text(&updated);
            Some(DeterministicEditResult {
                applied: updated != source_text,
                output,
                intent: EditIntent::General,
                scope: CommandScope::All,
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
            let replace_result = apply_edit(source_text, &target, &replacement);
            let output = cleanup_edited_text(&replace_result.output);
            Some(DeterministicEditResult {
                applied: replace_result.output != source_text,
                output,
                intent: EditIntent::Replace,
                scope: CommandScope::All,
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
    }
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
        parse_clear_all_command(instruction),
        parse_delete_command(instruction),
        parse_replace_command(instruction),
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

fn parse_clear_all_command(instruction: &str) -> Option<ParsedCommand> {
    CLEAR_ALL_COMMAND
        .is_match(instruction)
        .then_some(ParsedCommand {
            kind: CommandKind::ClearAll,
            target: None,
            replacement: None,
        })
}

fn parse_delete_command(instruction: &str) -> Option<ParsedCommand> {
    let captures = DELETE_COMMAND.captures(instruction)?;
    let target = normalize_command_term(captures.get(1)?.as_str(), true);
    if target.is_empty()
        || DELETE_ALL_TARGET.is_match(&target)
        || is_ambiguous_pronoun_target(&target)
    {
        return None;
    }
    Some(ParsedCommand {
        kind: CommandKind::DeleteTerm,
        target: Some(target),
        replacement: None,
    })
}

fn parse_replace_command(instruction: &str) -> Option<ParsedCommand> {
    let captures = REPLACE_COMMAND.captures(instruction)?;
    let from = normalize_command_term(captures.get(1)?.as_str(), true);
    let to = normalize_replacement_term(captures.get(2)?.as_str());
    if from.is_empty() || to.is_empty() || is_ambiguous_pronoun_target(&from) {
        return None;
    }
    Some(ParsedCommand {
        kind: CommandKind::ReplaceTerm,
        target: Some(from),
        replacement: Some(to),
    })
}

fn apply_edit(source_text: &str, target: &str, replacement: &str) -> ReplaceApplyResult {
    let matches = find_target_matches(source_text, target);
    if matches.is_empty() {
        return ReplaceApplyResult {
            output: source_text.to_string(),
            matched_count: 0,
        };
    }
    ReplaceApplyResult {
        output: replace_target_matches(source_text, target, |matched| {
            apply_replacement_casing(matched, replacement)
        }),
        matched_count: matches.len(),
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
