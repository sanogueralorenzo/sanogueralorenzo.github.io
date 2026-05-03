use super::prompts::truncate_chars_exact;
use crate::sessions::shared::models::SessionMeta;
use anyhow::{Context, Result, bail};
use std::fs;
use std::process::Command;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const TITLE_MIN_CHARS: usize = 18;
const TITLE_MAX_CHARS: usize = 36;
const TITLE_INPUT_MAX_CHARS: usize = 2000;
const TITLE_MODEL: &str = "gpt-5.1-codex-mini";

pub(crate) fn generate_session_title(
    target: &SessionMeta,
    first_user_prompt: &str,
) -> Result<String> {
    let input = first_user_prompt.trim();
    if input.is_empty() {
        bail!("first user prompt is empty");
    }

    let prompt = build_title_generation_prompt(&truncate_chars_exact(input, TITLE_INPUT_MAX_CHARS));

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0));
    let schema_file = std::env::temp_dir().join(format!(
        "codex-core-title-schema-{}-{}.json",
        std::process::id(),
        now.as_nanos()
    ));
    let output_file = std::env::temp_dir().join(format!(
        "codex-core-title-output-{}-{}.txt",
        std::process::id(),
        now.as_nanos()
    ));

    let schema = serde_json::json!({
        "type": "object",
        "additionalProperties": false,
        "required": ["title"],
        "properties": {
            "title": {
                "type": "string",
                "minLength": TITLE_MIN_CHARS,
                "maxLength": TITLE_MAX_CHARS
            }
        }
    });
    fs::write(&schema_file, serde_json::to_string_pretty(&schema)?)
        .with_context(|| format!("failed writing {}", schema_file.display()))?;

    let mut command = Command::new("codex");
    command
        .arg("-a")
        .arg("never")
        .arg("-s")
        .arg("read-only")
        .arg("-m")
        .arg(TITLE_MODEL)
        .arg("-c")
        .arg("model_reasoning_effort=\"low\"")
        .arg("-c")
        .arg("web_search=\"disabled\"");

    if let Some(cwd) = target.cwd.as_deref() {
        let cwd_path = std::path::Path::new(cwd);
        if cwd_path.exists() {
            command.arg("-C").arg(cwd);
        }
    }

    command
        .arg("exec")
        .arg("--ephemeral")
        .arg("--skip-git-repo-check")
        .arg("--output-schema")
        .arg(&schema_file)
        .arg("--output-last-message")
        .arg(&output_file)
        .arg(prompt);

    let output = command
        .output()
        .context("failed running codex exec for title generation")?;

    let _ = fs::remove_file(&schema_file);

    if !output.status.success() {
        let _ = fs::remove_file(&output_file);
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let detail = if !stderr.is_empty() {
            stderr
        } else if !stdout.is_empty() {
            stdout
        } else {
            format!("process exited with status {}", output.status)
        };
        bail!("codex title generation failed: {detail}");
    }

    let raw = fs::read_to_string(&output_file)
        .with_context(|| format!("failed reading {}", output_file.display()))?;
    let _ = fs::remove_file(&output_file);

    parse_generated_title(&raw)
        .ok_or_else(|| anyhow::anyhow!("title generation returned an invalid title"))
}

fn build_title_generation_prompt(first_user_prompt: &str) -> String {
    [
        "You are a helpful assistant. You will be presented with a user prompt, and your job is to provide a short title for a task that will be created from that prompt.",
        "The tasks typically have to do with coding-related tasks, for example requests for bug fixes or questions about a codebase. The title you generate will be shown in the UI to represent the prompt.",
        "Generate a concise UI title (18-36 characters) for this task.",
        "Return only the title. No quotes or trailing punctuation.",
        "Do not use markdown or formatting characters.",
        "If the task includes a ticket reference (e.g. ABC-123), include it verbatim.",
        "",
        "Generate a clear, informative task title based solely on the prompt provided. Follow the rules below to ensure consistency, readability, and usefulness.",
        "",
        "How to write a good title:",
        "Generate a single-line title that captures the question or core change requested. The title should be easy to scan and useful in changelogs or review queues.",
        "- Use an imperative verb first: \"Add\", \"Fix\", \"Update\", \"Refactor\", \"Remove\", \"Locate\", \"Find\", etc.",
        "- Aim for 18-36 characters; keep under 5 words where possible.",
        "- Capitalize only the first word (unless locale requires otherwise).",
        "- Write the title in the user's locale.",
        "- Do not use punctuation at the end.",
        "- Output the title as plain text with no surrounding quotes or backticks.",
        "- Use precise, non-redundant language.",
        "- Translate fixed phrases into the user's locale (e.g., \"Fix bug\" -> \"Corrige el error\" in Spanish-ES), but leave code terms in English unless a widely adopted translation exists.",
        "- If the user provides a title explicitly, reuse it (translated if needed) and skip generation logic.",
        "- Make it clear when the user is requesting changes (use verbs like \"Fix\", \"Add\", etc) vs asking a question (use verbs like \"Find\", \"Locate\", \"Count\").",
        "- Do NOT respond to the user, answer questions, or attempt to solve the problem; just write a title that can represent the user's query.",
        "",
        "Examples:",
        "- User: \"Can we add dark-mode support to the settings page?\" -> Add dark-mode support",
        "- User: \"Fehlerbehebung: Beim Anmelden erscheint 500.\" (de-DE) -> Login-Fehler 500 beheben",
        "- User: \"Refactoriser le composant sidebar pour réduire le code dupliqué.\" (fr-FR) -> Refactoriser composant sidebar",
        "- User: \"How do I fix our login bug?\" -> Troubleshoot login bug",
        "- User: \"Where in the codebase is foo_bar created\" -> Locate foo_bar",
        "- User: \"what's 2+2\" -> Calculate 2+2",
        "",
        "By following these conventions, your titles will be readable, changelog-friendly, and helpful to both users and downstream tools.",
        "",
        "User prompt:",
        first_user_prompt,
    ]
    .join("\n")
}

fn parse_generated_title(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }

    if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(trimmed)
        && let Some(title) = parsed.get("title").and_then(serde_json::Value::as_str)
    {
        return normalize_generated_title(title);
    }

    normalize_generated_title(trimmed)
}

fn normalize_generated_title(raw: &str) -> Option<String> {
    let first_line = raw
        .replace("\r\n", "\n")
        .lines()
        .find(|line| !line.trim().is_empty())?
        .trim()
        .to_string();

    let without_prefix = strip_title_prefix(&first_line);
    let without_quotes =
        without_prefix.trim_matches(|c| matches!(c, '`' | '"' | '\'' | '“' | '”' | '‘' | '’'));
    let collapsed = without_quotes
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    let no_trailing_punctuation = collapsed
        .trim_end_matches(|c| matches!(c, '.' | '?' | '!'))
        .trim();

    if no_trailing_punctuation.is_empty() {
        return None;
    }

    let len = no_trailing_punctuation.chars().count();
    if len < TITLE_MIN_CHARS {
        return None;
    }
    if len > TITLE_MAX_CHARS {
        let truncated: String = no_trailing_punctuation
            .chars()
            .take(TITLE_MAX_CHARS - 1)
            .collect::<String>()
            .trim_end()
            .to_string();
        return Some(format!("{truncated}…"));
    }

    Some(no_trailing_punctuation.to_string())
}

fn strip_title_prefix(value: &str) -> String {
    let trimmed = value.trim_start();

    let mut chars = trimmed.chars();
    for expected in ['t', 'i', 't', 'l', 'e'] {
        let Some(current) = chars.next() else {
            return trimmed.to_string();
        };
        if !current.eq_ignore_ascii_case(&expected) {
            return trimmed.to_string();
        }
    }

    let Some(next) = chars.next() else {
        return trimmed.to_string();
    };
    if next != ':' && !next.is_whitespace() {
        return trimmed.to_string();
    }

    let mut suffix = chars.collect::<String>();
    if next == ':' {
        suffix = suffix.trim_start().to_string();
    }

    suffix.trim_start().to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_generated_title_matches_desktop_rules() {
        let value = normalize_generated_title("\ntitle:   Add dark-mode support.\n")
            .expect("expected title");
        assert_eq!(value, "Add dark-mode support");
    }

    #[test]
    fn normalize_generated_title_rejects_short_values() {
        assert!(normalize_generated_title("Fix bug").is_none());
    }

    #[test]
    fn normalize_generated_title_truncates_with_ellipsis() {
        let long = "Refactor feature state management for deterministic updates";
        let title = normalize_generated_title(long).expect("expected title");
        assert!(title.ends_with('…'));
        assert!(title.chars().count() <= TITLE_MAX_CHARS);
    }

    #[test]
    fn strip_title_prefix_requires_separator() {
        assert_eq!(
            strip_title_prefix("title: Add session merge"),
            "Add session merge"
        );
        assert_eq!(
            strip_title_prefix("Title Add session merge"),
            "Add session merge"
        );
        assert_eq!(strip_title_prefix("titled feature"), "titled feature");
    }

    #[test]
    fn truncate_chars_exact_keeps_hard_limit_without_suffix() {
        let value = truncate_chars_exact("abcd", 3);
        assert_eq!(value, "abc");
    }
}
