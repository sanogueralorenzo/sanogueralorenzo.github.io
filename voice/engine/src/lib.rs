use jni::objects::{JClass, JString};
use jni::sys::{jboolean, jstring};
use jni::JNIEnv;
use once_cell::sync::Lazy;
use regex::{Captures, Regex};

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

#[cfg(test)]
mod tests {
    use super::*;

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
}
