use super::*;

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
