use super::PullRequestReference;
use super::ReviewCommentFailure;
use super::ReviewRunResult;
use super::github::PullRequestView;
use super::github::run_gh;
use super::workspace::ReviewFinding;
use super::workspace::ReviewLineRange;
use super::workspace::ReviewOutputEvent;
use crate::agents::ReviewPublishMode;
use crate::core::temp::temp_file_path;
use anyhow::{Context, Result, bail};
use serde::Serialize;
use std::collections::HashMap;
use std::collections::HashSet;
use std::fs;
use std::path::Path;
use std::process::Command;

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub(super) struct FileDiffLines {
    left: HashSet<u32>,
    right: HashSet<u32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DiffSide {
    Left,
    Right,
}

impl DiffSide {
    fn as_github_value(self) -> &'static str {
        match self {
            Self::Left => "LEFT",
            Self::Right => "RIGHT",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct CommentTarget {
    line: u32,
    side: DiffSide,
}

#[derive(Debug, Clone, Serialize)]
struct PendingReviewComment {
    path: String,
    line: u32,
    side: String,
    body: String,
}

pub(super) fn collect_changed_diff_lines(
    repo_dir: &Path,
    base_ref_name: &str,
) -> Result<HashMap<String, FileDiffLines>> {
    let diff_target = format!("origin/{base_ref_name}...HEAD");
    let output = Command::new("git")
        .current_dir(repo_dir)
        .arg("diff")
        .arg("--unified=0")
        .arg("--no-color")
        .arg(&diff_target)
        .output()
        .context("failed to launch git diff")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        bail!("git diff failed: {}", stderr.trim());
    }

    Ok(parse_changed_diff_lines(&String::from_utf8_lossy(
        &output.stdout,
    )))
}

fn parse_changed_diff_lines(diff_text: &str) -> HashMap<String, FileDiffLines> {
    let mut changed_lines: HashMap<String, FileDiffLines> = HashMap::new();
    let mut current_old_path: Option<String> = None;
    let mut current_new_path: Option<String> = None;
    let mut current_old_line = 0u32;
    let mut current_new_line = 0u32;

    for line in diff_text.lines() {
        if let Some(header) = line.strip_prefix("diff --git a/") {
            if let Some((old_path, new_path)) = header.split_once(" b/") {
                current_old_path = Some(old_path.to_string());
                current_new_path = Some(new_path.to_string());
            }
            continue;
        }

        if let Some(hunk) = line.strip_prefix("@@ ") {
            let Some((old_part, rest)) = hunk.split_once(' ') else {
                continue;
            };
            current_old_line = old_part
                .trim_start_matches('-')
                .split(',')
                .next()
                .unwrap_or("0")
                .parse::<u32>()
                .unwrap_or(0);
            let new_span = rest
                .trim_start_matches('+')
                .split(' ')
                .next()
                .unwrap_or_default();
            current_new_line = new_span
                .split(',')
                .next()
                .unwrap_or("0")
                .parse::<u32>()
                .unwrap_or(0);
            continue;
        }

        if line.starts_with('+') && !line.starts_with("+++") {
            if let Some(path) = current_new_path.as_ref() {
                changed_lines
                    .entry(path.clone())
                    .or_default()
                    .right
                    .insert(current_new_line);
            }
            current_new_line += 1;
            continue;
        }

        if line.starts_with('-') && !line.starts_with("---") {
            if let Some(path) = current_old_path.as_ref() {
                changed_lines
                    .entry(path.clone())
                    .or_default()
                    .left
                    .insert(current_old_line);
            }
            current_old_line += 1;
            continue;
        }

        if line.starts_with(' ') {
            current_old_line += 1;
            current_new_line += 1;
            continue;
        }

        if line == "\\ No newline at end of file" {
            continue;
        }

        if let Some(path) = line.strip_prefix("--- a/") {
            changed_lines.entry(path.to_string()).or_default();
            continue;
        }

        if let Some(path) = line.strip_prefix("+++ b/") {
            changed_lines.entry(path.to_string()).or_default();
        }
    }

    changed_lines
}

pub(super) fn post_review_comments(
    pr_ref: &PullRequestReference,
    repo_dir: &Path,
    pull_request: &PullRequestView,
    review: ReviewOutputEvent,
    changed_lines: &HashMap<String, FileDiffLines>,
    publish_mode: ReviewPublishMode,
) -> Result<ReviewRunResult> {
    match publish_mode {
        ReviewPublishMode::Publish => {
            post_review_comments_publish(pr_ref, repo_dir, pull_request, review, changed_lines)
        }
        ReviewPublishMode::Pending => {
            post_review_comments_pending(pr_ref, repo_dir, pull_request, review, changed_lines)
        }
    }
}

fn post_review_comments_publish(
    pr_ref: &PullRequestReference,
    repo_dir: &Path,
    pull_request: &PullRequestView,
    review: ReviewOutputEvent,
    changed_lines: &HashMap<String, FileDiffLines>,
) -> Result<ReviewRunResult> {
    let mut posted_comments = 0usize;
    let mut failed_comments = 0usize;
    let mut failed_comment_details = Vec::new();
    let summary = summarize_review(&review);

    for finding in &review.findings {
        let normalized_path =
            normalize_comment_path(&finding.code_location.absolute_file_path, repo_dir).ok();
        let path_for_comment = normalized_path.clone().unwrap_or_else(|| {
            finding
                .code_location
                .absolute_file_path
                .display()
                .to_string()
        });

        let body = render_inline_comment_body(finding);
        let inline_error = match normalized_path.as_deref() {
            Some(path) => {
                match select_comment_target(
                    &finding.code_location.line_range,
                    changed_lines.get(path),
                ) {
                    Some(target) => post_inline_comment(
                        pr_ref,
                        &pull_request.head_ref_oid,
                        path,
                        target.line,
                        target.side.as_github_value(),
                        &body,
                    )
                    .err(),
                    None => Some(anyhow::anyhow!(
                        "No changed diff line matched this finding on either side of the PR."
                    )),
                }
            }
            None => Some(anyhow::anyhow!(
                "comment path is outside checked out repo: {}",
                finding.code_location.absolute_file_path.display()
            )),
        };

        if let Some(error) = inline_error {
            let top_level_body = render_top_level_comment_body(
                pr_ref,
                &pull_request.head_ref_oid,
                finding,
                &path_for_comment,
            );
            if let Err(top_level_error) = post_top_level_comment(pr_ref, &top_level_body) {
                failed_comments += 1;
                failed_comment_details.push(ReviewCommentFailure {
                    title: finding.title.trim().to_string(),
                    path: Some(path_for_comment),
                    start_line: finding.code_location.line_range.start,
                    end_line: finding.code_location.line_range.end,
                    reason: format!(
                        "Inline comment failed: {}. Top-level comment failed: {}",
                        error, top_level_error
                    ),
                });
            } else {
                posted_comments += 1;
            }
        } else {
            posted_comments += 1;
        }
    }

    Ok(ReviewRunResult {
        review_id: String::new(),
        publish_mode: ReviewPublishMode::Publish,
        owner: pr_ref.owner.clone(),
        repo: pr_ref.repo.clone(),
        number: pull_request.number,
        url: pull_request.url.clone(),
        posted_comments,
        failed_comments,
        failed_comment_details,
        summary,
    })
}

fn post_review_comments_pending(
    pr_ref: &PullRequestReference,
    repo_dir: &Path,
    pull_request: &PullRequestView,
    review: ReviewOutputEvent,
    changed_lines: &HashMap<String, FileDiffLines>,
) -> Result<ReviewRunResult> {
    let summary = summarize_review(&review);
    let mut pending_comments = Vec::new();
    let mut pending_body_sections = Vec::new();

    for finding in &review.findings {
        let normalized_path =
            normalize_comment_path(&finding.code_location.absolute_file_path, repo_dir).ok();
        let path_for_comment = normalized_path.clone().unwrap_or_else(|| {
            finding
                .code_location
                .absolute_file_path
                .display()
                .to_string()
        });
        let body = render_inline_comment_body(finding);

        match normalized_path.as_deref() {
            Some(path) => {
                match select_comment_target(
                    &finding.code_location.line_range,
                    changed_lines.get(path),
                ) {
                    Some(target) => pending_comments.push(PendingReviewComment {
                        path: path.to_string(),
                        line: target.line,
                        side: target.side.as_github_value().to_string(),
                        body,
                    }),
                    None => pending_body_sections.push(render_top_level_comment_body(
                        pr_ref,
                        &pull_request.head_ref_oid,
                        finding,
                        &path_for_comment,
                    )),
                }
            }
            None => pending_body_sections.push(render_top_level_comment_body(
                pr_ref,
                &pull_request.head_ref_oid,
                finding,
                &path_for_comment,
            )),
        }
    }

    let pending_body = render_pending_review_body(&pending_body_sections);
    let mut failed_comment_details = Vec::new();
    let total_findings = review.findings.len();
    let (posted_comments, failed_comments) = if total_findings == 0 {
        (0, 0)
    } else {
        match post_pending_review(
            pr_ref,
            pull_request,
            &pending_comments,
            pending_body.as_deref(),
        ) {
            Ok(()) => (total_findings, 0),
            Err(error) => {
                for finding in &review.findings {
                    let normalized_path =
                        normalize_comment_path(&finding.code_location.absolute_file_path, repo_dir)
                            .ok();
                    let path_for_comment = normalized_path.unwrap_or_else(|| {
                        finding
                            .code_location
                            .absolute_file_path
                            .display()
                            .to_string()
                    });
                    failed_comment_details.push(ReviewCommentFailure {
                        title: finding.title.trim().to_string(),
                        path: Some(path_for_comment),
                        start_line: finding.code_location.line_range.start,
                        end_line: finding.code_location.line_range.end,
                        reason: format!("Pending review creation failed: {error}"),
                    });
                }
                (0, total_findings)
            }
        }
    };

    Ok(ReviewRunResult {
        review_id: String::new(),
        publish_mode: ReviewPublishMode::Pending,
        owner: pr_ref.owner.clone(),
        repo: pr_ref.repo.clone(),
        number: pull_request.number,
        url: pull_request.url.clone(),
        posted_comments,
        failed_comments,
        failed_comment_details,
        summary,
    })
}

fn summarize_review(review: &ReviewOutputEvent) -> String {
    let explanation = review.overall_explanation.trim();
    if explanation.is_empty() {
        return review.overall_correctness.clone();
    }
    if review.overall_correctness.trim().is_empty() {
        return explanation.to_string();
    }
    format!("{}: {}", review.overall_correctness.trim(), explanation)
}

fn normalize_comment_path(path: &Path, repo_dir: &Path) -> Result<String> {
    let relative = path.strip_prefix(repo_dir).with_context(|| {
        format!(
            "comment path is outside checked out repo: {}",
            path.display()
        )
    })?;
    Ok(relative.to_string_lossy().into_owned())
}

fn select_comment_target(
    line_range: &ReviewLineRange,
    changed_lines: Option<&FileDiffLines>,
) -> Option<CommentTarget> {
    let changed_lines = changed_lines?;
    let end = line_range.end.max(line_range.start);
    for line in line_range.start..=end {
        if changed_lines.right.contains(&line) {
            return Some(CommentTarget {
                line,
                side: DiffSide::Right,
            });
        }
    }
    for line in line_range.start..=end {
        if changed_lines.left.contains(&line) {
            return Some(CommentTarget {
                line,
                side: DiffSide::Left,
            });
        }
    }
    None
}

fn render_inline_comment_body(finding: &ReviewFinding) -> String {
    let mut lines = vec![
        render_finding_heading(finding),
        String::new(),
        finding.body.trim().to_string(),
    ];
    lines.push(format!("Confidence: {:.2}", finding.confidence_score));
    lines.join("\n")
}

fn render_top_level_comment_body(
    pr_ref: &PullRequestReference,
    head_ref_oid: &str,
    finding: &ReviewFinding,
    path: &str,
) -> String {
    let line_range = &finding.code_location.line_range;
    let location = if line_range.end > line_range.start {
        format!("{path}:{}-{}", line_range.start, line_range.end)
    } else {
        format!("{path}:{}", line_range.start)
    };
    let location_link = github_blob_line_url(pr_ref, head_ref_oid, path, line_range);

    let mut lines = vec![
        render_finding_heading(finding),
        String::new(),
        format!("File: [`{location}`]({location_link})"),
        String::new(),
        finding.body.trim().to_string(),
    ];
    lines.push(format!("Confidence: {:.2}", finding.confidence_score));
    lines.join("\n")
}

fn render_pending_review_body(sections: &[String]) -> Option<String> {
    let sections: Vec<&str> = sections
        .iter()
        .map(String::as_str)
        .filter(|section| !section.trim().is_empty())
        .collect();
    if sections.is_empty() {
        return None;
    }
    Some(sections.join("\n\n---\n\n"))
}

fn github_blob_line_url(
    pr_ref: &PullRequestReference,
    head_ref_oid: &str,
    path: &str,
    line_range: &ReviewLineRange,
) -> String {
    let path = path.trim_start_matches('/');
    let anchor = if line_range.end > line_range.start {
        format!("#L{}-L{}", line_range.start, line_range.end)
    } else {
        format!("#L{}", line_range.start)
    };
    format!(
        "https://github.com/{}/{}/blob/{}/{}{}",
        pr_ref.owner, pr_ref.repo, head_ref_oid, path, anchor
    )
}

fn render_finding_heading(finding: &ReviewFinding) -> String {
    let title = strip_priority_prefix(finding.title.trim());
    match render_priority_badge_markdown(finding.priority) {
        Some(badge) => format!("**<sub><sub>{badge}</sub></sub>  {title}**"),
        None => title.to_string(),
    }
}

fn strip_priority_prefix(title: &str) -> &str {
    let trimmed = title.trim();
    for prefix in ["[P0]", "[P1]", "[P2]", "[P3]"] {
        if let Some(remaining) = trimmed.strip_prefix(prefix) {
            return remaining.trim_start();
        }
    }
    trimmed
}

fn render_priority_badge_markdown(priority: Option<i32>) -> Option<String> {
    let priority = priority?;
    let color = match priority {
        0 | 1 => "red",
        2 => "orange",
        3 => "yellow",
        _ => return None,
    };
    Some(format!(
        "![P{priority} Badge](https://img.shields.io/badge/P{priority}-{color}?style=flat)"
    ))
}

fn post_inline_comment(
    pr_ref: &PullRequestReference,
    commit_id: &str,
    path: &str,
    line: u32,
    side: &str,
    body: &str,
) -> Result<()> {
    if line == 0 {
        bail!("codex review returned invalid line 0 for {path}");
    }
    if body.trim().is_empty() {
        bail!("codex review returned an empty comment body for {path}:{line}");
    }

    let payload_path = temp_file_path("codex-core-pr-review-comment", "json");
    let payload = serde_json::json!({
        "body": body.trim(),
        "commit_id": commit_id,
        "path": path,
        "line": line,
        "side": side
    });
    fs::write(
        &payload_path,
        serde_json::to_vec(&payload).context("failed to serialize PR comment payload")?,
    )
    .with_context(|| format!("failed to write {}", payload_path.display()))?;

    let result = run_gh(
        vec![
            "api".to_string(),
            format!(
                "repos/{}/{}/pulls/{}/comments",
                pr_ref.owner, pr_ref.repo, pr_ref.number
            ),
            "-H".to_string(),
            "Accept: application/vnd.github+json".to_string(),
            "--input".to_string(),
            payload_path.to_string_lossy().into_owned(),
        ],
        None,
    );
    let _ = fs::remove_file(&payload_path);
    result?;
    Ok(())
}

fn post_top_level_comment(pr_ref: &PullRequestReference, body: &str) -> Result<()> {
    if body.trim().is_empty() {
        bail!("codex review returned an empty top-level comment body");
    }

    let payload_path = temp_file_path("codex-core-pr-top-level-comment", "json");
    let payload = serde_json::json!({
        "body": body.trim(),
    });
    fs::write(
        &payload_path,
        serde_json::to_vec(&payload).context("failed to serialize PR top-level comment payload")?,
    )
    .with_context(|| format!("failed to write {}", payload_path.display()))?;

    let result = run_gh(
        vec![
            "api".to_string(),
            format!(
                "repos/{}/{}/issues/{}/comments",
                pr_ref.owner, pr_ref.repo, pr_ref.number
            ),
            "-H".to_string(),
            "Accept: application/vnd.github+json".to_string(),
            "--input".to_string(),
            payload_path.to_string_lossy().into_owned(),
        ],
        None,
    );
    let _ = fs::remove_file(&payload_path);
    result?;
    Ok(())
}

fn post_pending_review(
    pr_ref: &PullRequestReference,
    pull_request: &PullRequestView,
    comments: &[PendingReviewComment],
    body: Option<&str>,
) -> Result<()> {
    let trimmed_body = body.map(str::trim).filter(|value| !value.is_empty());
    if comments.is_empty() && trimmed_body.is_none() {
        return Ok(());
    }

    let payload_path = temp_file_path("codex-core-pr-pending-review", "json");
    let mut payload = serde_json::Map::new();
    payload.insert(
        "commit_id".to_string(),
        serde_json::Value::String(pull_request.head_ref_oid.clone()),
    );
    if let Some(body) = trimmed_body {
        payload.insert(
            "body".to_string(),
            serde_json::Value::String(body.to_string()),
        );
    }
    if !comments.is_empty() {
        payload.insert(
            "comments".to_string(),
            serde_json::to_value(comments)
                .context("failed to serialize pending review comments")?,
        );
    }

    fs::write(
        &payload_path,
        serde_json::to_vec(&serde_json::Value::Object(payload))
            .context("failed to serialize pending review payload")?,
    )
    .with_context(|| format!("failed to write {}", payload_path.display()))?;

    let result = run_gh(
        vec![
            "api".to_string(),
            format!(
                "repos/{}/{}/pulls/{}/reviews",
                pr_ref.owner, pr_ref.repo, pr_ref.number
            ),
            "-H".to_string(),
            "Accept: application/vnd.github+json".to_string(),
            "--input".to_string(),
            payload_path.to_string_lossy().into_owned(),
        ],
        None,
    );
    let _ = fs::remove_file(&payload_path);
    result?;
    Ok(())
}

#[cfg(test)]
pub(super) mod tests {
    use super::*;

    #[test]
    fn parses_changed_diff_lines_from_diff() {
        let diff = "\
diff --git a/src/app.rs b/src/app.rs
index 1111111..2222222 100644
--- a/src/app.rs
+++ b/src/app.rs
@@ -10,1 +11,2 @@
-let old = false;
+let added = true;
+let next = true;
@@ -20 +22,0 @@
-let removed = true;
";
        let changed = parse_changed_diff_lines(diff);
        let lines = changed.get("src/app.rs").unwrap();
        assert!(lines.right.contains(&11));
        assert!(lines.right.contains(&12));
        assert!(lines.left.contains(&10));
        assert!(lines.left.contains(&20));
        assert!(!lines.right.contains(&22));
    }

    #[test]
    fn strip_priority_prefix_removes_leading_priority_tag() {
        assert_eq!(
            strip_priority_prefix("[P2] Keep the chatbot label in sync"),
            "Keep the chatbot label in sync"
        );
    }

    #[test]
    fn strip_priority_prefix_keeps_title_without_priority_tag() {
        assert_eq!(
            strip_priority_prefix("Keep the chatbot label in sync"),
            "Keep the chatbot label in sync"
        );
    }
}
