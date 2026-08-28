use super::PullRequestReference;
use crate::agents::StateLayout;
use crate::core::temp::temp_file_path;
use anyhow::{Context, Result, bail};
use serde::Deserialize;
use serde::Serialize;
use std::fs;
use std::io::Write;
use std::path::Path;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use uuid::Uuid;

use super::github::PullRequestView;
use super::github::run_gh;

pub(super) struct ReviewWorkspace {
    cache_repo_dir: PathBuf,
    pub(super) repo_dir: PathBuf,
}

pub(super) struct UpstreamReviewPrompts {
    pub(super) review_rubric: String,
    pub(super) base_branch_prompt: String,
    pub(super) base_branch_prompt_backup: String,
}

#[derive(Debug, Deserialize)]
pub(super) struct ReviewOutputEvent {
    pub(super) findings: Vec<ReviewFinding>,
    pub(super) overall_correctness: String,
    pub(super) overall_explanation: String,
}

#[derive(Debug, Deserialize)]
pub(super) struct ReviewFinding {
    pub(super) title: String,
    pub(super) body: String,
    pub(super) confidence_score: f32,
    pub(super) priority: Option<i32>,
    pub(super) code_location: ReviewCodeLocation,
}

#[derive(Debug, Deserialize)]
pub(super) struct ReviewCodeLocation {
    pub(super) absolute_file_path: PathBuf,
    pub(super) line_range: ReviewLineRange,
}

#[derive(Debug, Deserialize, Clone, Serialize)]
pub(super) struct ReviewLineRange {
    pub(super) start: u32,
    pub(super) end: u32,
}

impl Drop for ReviewWorkspace {
    fn drop(&mut self) {
        let _ = Command::new("git")
            .arg("-C")
            .arg(&self.cache_repo_dir)
            .args(["worktree", "remove", "--force"])
            .arg(&self.repo_dir)
            .output();
        let _ = Command::new("git")
            .arg("-C")
            .arg(&self.cache_repo_dir)
            .args(["worktree", "prune"])
            .output();
        let _ = fs::remove_dir_all(&self.repo_dir);
    }
}

pub(super) fn checkout_pull_request(
    layout: &StateLayout,
    pr_ref: &PullRequestReference,
    pull_request: &PullRequestView,
) -> Result<ReviewWorkspace> {
    let cache_repo_dir = layout
        .root
        .join("repos")
        .join(&pr_ref.owner)
        .join(&pr_ref.repo);
    let worktree_dir = layout
        .root
        .join("worktrees")
        .join(&pr_ref.owner)
        .join(&pr_ref.repo)
        .join(format!("pr-{}-{}", pr_ref.number, Uuid::new_v4()));

    fs::create_dir_all(
        cache_repo_dir
            .parent()
            .context("cache repo path missing parent")?,
    )
    .with_context(|| format!("failed to create parent for {}", cache_repo_dir.display()))?;
    fs::create_dir_all(
        worktree_dir
            .parent()
            .context("worktree path missing parent")?,
    )
    .with_context(|| format!("failed to create parent for {}", worktree_dir.display()))?;

    if cache_repo_dir.exists() {
        refresh_cached_repo(&cache_repo_dir)?;
    } else {
        clone_repo_cache(&cache_repo_dir, pr_ref)?;
    }
    fetch_pull_request_head_ref(&cache_repo_dir, pr_ref)?;
    add_pull_request_worktree(&cache_repo_dir, &worktree_dir, pr_ref)?;
    validate_base_branch_exists(&worktree_dir, &pull_request.base_ref_name)?;

    Ok(ReviewWorkspace {
        cache_repo_dir,
        repo_dir: worktree_dir,
    })
}

fn clone_repo_cache(cache_repo_dir: &Path, pr_ref: &PullRequestReference) -> Result<()> {
    run_gh(
        vec![
            "repo".to_string(),
            "clone".to_string(),
            pr_ref.repo_name_with_owner(),
            cache_repo_dir.to_string_lossy().into_owned(),
            "--".to_string(),
            "--quiet".to_string(),
        ],
        None,
    )?;
    Ok(())
}

fn refresh_cached_repo(cache_repo_dir: &Path) -> Result<()> {
    if !cache_repo_dir.join(".git").exists() {
        bail!(
            "Cached repo path is not a git repository: {}",
            cache_repo_dir.display()
        );
    }

    run_git(cache_repo_dir, &["fetch", "--all", "--prune"])
}

fn fetch_pull_request_head_ref(cache_repo_dir: &Path, pr_ref: &PullRequestReference) -> Result<()> {
    let remote_ref = format!(
        "refs/pull/{}/head:refs/remotes/origin/pr/{}",
        pr_ref.number, pr_ref.number
    );
    run_git(cache_repo_dir, &["fetch", "--force", "origin", &remote_ref])
}

fn add_pull_request_worktree(
    cache_repo_dir: &Path,
    worktree_dir: &Path,
    pr_ref: &PullRequestReference,
) -> Result<()> {
    let pr_ref_name = format!("refs/remotes/origin/pr/{}", pr_ref.number);
    run_git(
        cache_repo_dir,
        &[
            "worktree",
            "add",
            "--force",
            "--detach",
            worktree_dir.to_string_lossy().as_ref(),
            &pr_ref_name,
        ],
    )
}

fn validate_base_branch_exists(worktree_dir: &Path, base_ref_name: &str) -> Result<()> {
    let origin_base = format!("origin/{base_ref_name}");
    run_git(worktree_dir, &["rev-parse", "--verify", &origin_base]).map(|_| ())
}

fn run_git(repo_dir: &Path, args: &[&str]) -> Result<()> {
    let output = Command::new("git")
        .current_dir(repo_dir)
        .args(args)
        .output()
        .with_context(|| format!("failed to launch git {}", args.join(" ")))?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let trimmed = stderr.trim();
        if trimmed.is_empty() {
            bail!("git {} failed", args.join(" "));
        }
        bail!("git {} failed: {}", args.join(" "), trimmed);
    }
    Ok(())
}

pub(super) fn load_upstream_review_prompts() -> Result<UpstreamReviewPrompts> {
    let review_rubric = fetch_upstream_file("codex-rs/core/review_prompt.md")?;
    let review_prompts_source = fetch_upstream_file("codex-rs/core/src/review_prompts.rs")?;

    Ok(UpstreamReviewPrompts {
        review_rubric,
        base_branch_prompt: extract_rust_string_constant(
            &review_prompts_source,
            "BASE_BRANCH_PROMPT",
        )?,
        base_branch_prompt_backup: extract_rust_string_constant(
            &review_prompts_source,
            "BASE_BRANCH_PROMPT_BACKUP",
        )?,
    })
}

fn fetch_upstream_file(path: &str) -> Result<String> {
    run_gh(
        vec![
            "api".to_string(),
            format!("repos/openai/codex/contents/{path}?ref=main"),
            "-H".to_string(),
            "Accept: application/vnd.github.raw".to_string(),
        ],
        None,
    )
    .with_context(|| format!("failed to fetch upstream {path} from openai/codex main"))
}

pub(super) fn extract_rust_string_constant(source: &str, constant_name: &str) -> Result<String> {
    let marker = format!("const {constant_name}: &str = ");
    let start = source
        .find(&marker)
        .with_context(|| format!("missing upstream constant {constant_name}"))?;
    let rhs_start = start + marker.len();
    let rhs = source[rhs_start..]
        .split_once(';')
        .map(|(value, _)| value.trim())
        .with_context(|| format!("failed to parse upstream constant {constant_name}"))?;

    if rhs.starts_with('"') {
        return serde_json::from_str(rhs)
            .with_context(|| format!("failed to decode upstream constant {constant_name}"));
    }

    bail!("unsupported upstream constant format for {constant_name}")
}

pub(super) fn resolve_merge_base(repo_dir: &Path, base_ref_name: &str) -> Result<Option<String>> {
    let origin_base = format!("origin/{base_ref_name}");
    let output = Command::new("git")
        .current_dir(repo_dir)
        .arg("merge-base")
        .arg("HEAD")
        .arg(&origin_base)
        .output()
        .context("failed to launch git merge-base")?;

    if !output.status.success() {
        return Ok(None);
    }

    let merge_base = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if merge_base.is_empty() {
        return Ok(None);
    }

    Ok(Some(merge_base))
}

pub(super) fn build_base_branch_review_request(
    prompts: &UpstreamReviewPrompts,
    base_ref_name: &str,
    merge_base: Option<&str>,
) -> String {
    if let Some(merge_base) = merge_base {
        return prompts
            .base_branch_prompt
            .replace("{baseBranch}", base_ref_name)
            .replace("{mergeBaseSha}", merge_base);
    }

    prompts
        .base_branch_prompt_backup
        .replace("{branch}", base_ref_name)
}

pub(super) fn run_codex_exec_review(repo_dir: &Path, prompt: &str) -> Result<ReviewOutputEvent> {
    let output_last_message = temp_file_path("codex-core-review-last-message", "txt");
    let mut command = Command::new("codex");
    command
        .current_dir(repo_dir)
        .env("NO_COLOR", "1")
        .arg("exec")
        .arg("--json")
        .arg("--full-auto")
        .arg("--output-last-message")
        .arg(&output_last_message)
        .arg("-");
    command.stdin(Stdio::piped());
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());

    let mut child = command.spawn().context("failed to launch codex exec")?;
    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(prompt.as_bytes())
            .context("failed to write review prompt to codex exec")?;
    }

    let output = child
        .wait_with_output()
        .context("failed while waiting for codex exec")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let trimmed = stderr.trim();
        if trimmed.is_empty() {
            bail!(
                "codex exec exited with status {}",
                output.status.code().unwrap_or(1)
            );
        }
        bail!(
            "codex exec exited with status {}: {}",
            output.status.code().unwrap_or(1),
            trimmed
        );
    }

    let last_message = fs::read_to_string(&output_last_message)
        .with_context(|| format!("failed to read {}", output_last_message.display()))?;
    let _ = fs::remove_file(&output_last_message);
    parse_review_output_event(&last_message)
}

fn parse_review_output_event(text: &str) -> Result<ReviewOutputEvent> {
    if let Ok(event) = serde_json::from_str::<ReviewOutputEvent>(text) {
        return Ok(event);
    }

    if let (Some(start), Some(end)) = (text.find('{'), text.rfind('}'))
        && start < end
        && let Some(slice) = text.get(start..=end)
        && let Ok(event) = serde_json::from_str::<ReviewOutputEvent>(slice)
    {
        return Ok(event);
    }

    bail!("codex exec review output was not valid review JSON")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn extracts_upstream_string_constant() {
        let source = r#"const BASE_BRANCH_PROMPT: &str = "hello {baseBranch}";"#;
        let value = extract_rust_string_constant(source, "BASE_BRANCH_PROMPT").unwrap();
        assert_eq!(value, "hello {baseBranch}");
    }
}
