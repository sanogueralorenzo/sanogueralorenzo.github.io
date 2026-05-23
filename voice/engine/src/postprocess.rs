use super::*;

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
