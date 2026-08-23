use super::*;

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
