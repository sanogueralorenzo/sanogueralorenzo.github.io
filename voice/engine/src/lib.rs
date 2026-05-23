use once_cell::sync::Lazy;
use regex::{Captures, Regex};

mod edit;
mod jni;
mod list_detection;
mod postprocess;
mod preprocess;

#[cfg(test)]
mod tests;

pub use edit::{
    analyze_instruction, is_strict_edit_command, post_replace_capitalization,
    should_allow_blank_output, try_apply_deterministic_edit, CommandKind, CommandScope,
    DeterministicEditResult, EditInstructionAnalysis, EditIntent, RuleConfidence,
};
use edit::{
    DeleteVerbRestriction, DeleteVerbSpec, ReplaceConnector, ReplaceVerbRestriction,
    ReplaceVerbSpec,
};
pub use list_detection::looks_like_list;
pub use postprocess::{
    clean_model_output, normalize_compose_input, normalize_compose_output_text,
    normalize_instruction_input, postprocess,
};
pub use preprocess::{preprocess, PreprocessResult};

#[cfg(test)]
pub(crate) use jni::sanitize_field;

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
