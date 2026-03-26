use super::StateLayout;
use super::task;
use anyhow::{Context, Result, bail};
use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use uuid::Uuid;

const DEFAULT_BASE_BRANCH: &str = "main";
const SPIKE_OUTPUT_FILE: &str = ".codex-spike-result.json";
const MAX_SPIKE_CONTEXT_COMMENTS: usize = 10;
const MAX_SPIKE_COMMENT_CHARS: usize = 600;

#[derive(Subcommand, Debug)]
pub(super) enum SpikeCommand {
    /// Run a Jira spike in a disposable worktree and post the outcome back to Jira
    Run(SpikeRunArgs),
}

#[derive(Args, Debug)]
pub(super) struct SpikeRunArgs {
    pub ticket: String,
    #[arg(long)]
    pub json: bool,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SpikeJobStatus {
    InProgress,
    Completed,
    Failed,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SpikeJob {
    pub id: String,
    pub ticket: String,
    pub summary: String,
    pub issue_url: String,
    pub repo_full_name: String,
    pub branch: String,
    pub status: SpikeJobStatus,
    pub current_step: String,
    pub created_at: String,
    pub updated_at: String,
    pub finished_at: Option<String>,
    pub result_summary: Option<String>,
    pub error: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct SpikeRunResult {
    pub spike_id: String,
    pub ticket: String,
    pub repo_full_name: String,
    pub branch: String,
    pub summary: String,
    pub status: SpikeJobStatus,
}

#[derive(Clone, Debug, Deserialize)]
struct JiraIssueFields {
    summary: String,
    #[serde(default)]
    description: Option<Value>,
}

#[derive(Clone, Debug, Deserialize)]
struct JiraIssueView {
    key: String,
    fields: JiraIssueFields,
}

#[derive(Clone, Debug, Deserialize)]
struct JiraCommentList {
    comments: Vec<JiraComment>,
}

#[derive(Clone, Debug, Deserialize)]
struct JiraComment {
    author: String,
    body: Value,
}

#[derive(Debug, Deserialize)]
struct CodexSpikeExecResult {
    summary: String,
    #[serde(default)]
    comment: Option<String>,
}

struct WorktreeGuard {
    cache_repo_path: PathBuf,
    worktree_path: PathBuf,
}

impl Drop for WorktreeGuard {
    fn drop(&mut self) {
        let _ = Command::new("git")
            .arg("-C")
            .arg(&self.cache_repo_path)
            .args(["worktree", "remove", "--force"])
            .arg(&self.worktree_path)
            .status();
        let _ = Command::new("git")
            .arg("-C")
            .arg(&self.cache_repo_path)
            .args(["worktree", "prune"])
            .status();
        let _ = fs::remove_dir_all(&self.worktree_path);
    }
}

pub(super) fn handle_spike(action: SpikeCommand, layout: &StateLayout) -> Result<()> {
    super::ensure_state_layout(layout)?;
    match action {
        SpikeCommand::Run(args) => run_spike(layout, args),
    }
}

fn run_spike(layout: &StateLayout, args: SpikeRunArgs) -> Result<()> {
    task::validate_ticket_key(&args.ticket)?;
    let issue = load_issue(&args.ticket)?;
    let existing_comments = load_issue_comments(&args.ticket)?;
    let project = task::project_for_ticket(layout, &issue.key)?;
    let branch = task::branch_name(&issue.key, &issue.fields.summary);
    let now = super::now_utc();
    let mut job = SpikeJob {
        id: Uuid::new_v4().to_string(),
        ticket: issue.key.clone(),
        summary: issue.fields.summary.clone(),
        issue_url: task::issue_url(&issue.key),
        repo_full_name: project.repo_full_name.clone(),
        branch: branch.clone(),
        status: SpikeJobStatus::InProgress,
        current_step: "preparing_repo".to_string(),
        created_at: now.clone(),
        updated_at: now,
        finished_at: None,
        result_summary: None,
        error: None,
    };
    write_spike_job(layout, &job)?;

    let result = run_spike_job(
        layout,
        &project.repo_full_name,
        &issue,
        &existing_comments,
        &branch,
        &mut job,
    );
    match result {
        Ok(run_result) => {
            if args.json {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&run_result)
                        .context("failed to serialize spike run result")?
                );
            } else {
                println!("Spike ID: {}", run_result.spike_id);
                println!("Ticket: {}", run_result.ticket);
                println!("Repo: {}", run_result.repo_full_name);
                println!("Branch: {}", run_result.branch);
                println!("Summary: {}", run_result.summary);
            }
            Ok(())
        }
        Err(error) => {
            job.status = SpikeJobStatus::Failed;
            job.current_step = "failed".to_string();
            job.updated_at = super::now_utc();
            job.finished_at = Some(job.updated_at.clone());
            job.error = Some(error.to_string());
            write_spike_job(layout, &job)?;
            Err(error)
        }
    }
}

fn run_spike_job(
    layout: &StateLayout,
    repo_full_name: &str,
    issue: &JiraIssueView,
    existing_comments: &[JiraComment],
    branch: &str,
    job: &mut SpikeJob,
) -> Result<SpikeRunResult> {
    let cache_repo_path = prepare_cache_repo(layout, repo_full_name, job)?;
    let worktree_path =
        create_spike_worktree(layout, &cache_repo_path, DEFAULT_BASE_BRANCH, branch)?;
    let _worktree_guard = WorktreeGuard {
        cache_repo_path,
        worktree_path: worktree_path.clone(),
    };

    job.current_step = "running_codex_exec".to_string();
    job.updated_at = super::now_utc();
    write_spike_job(layout, job)?;

    let exec_result = run_codex_spike(
        issue,
        existing_comments,
        branch,
        repo_full_name,
        &worktree_path,
    )?;

    if let Some(comment) = exec_result
        .comment
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
    {
        job.current_step = "posting_jira_comment".to_string();
        job.updated_at = super::now_utc();
        write_spike_job(layout, job)?;
        post_spike_comment(&issue.key, comment)?;
    }

    job.status = SpikeJobStatus::Completed;
    job.current_step = "completed".to_string();
    job.updated_at = super::now_utc();
    job.finished_at = Some(job.updated_at.clone());
    job.result_summary = Some(exec_result.summary.clone());
    write_spike_job(layout, job)?;

    Ok(SpikeRunResult {
        spike_id: job.id.clone(),
        ticket: job.ticket.clone(),
        repo_full_name: job.repo_full_name.clone(),
        branch: job.branch.clone(),
        summary: exec_result.summary,
        status: job.status,
    })
}

fn load_issue(ticket: &str) -> Result<JiraIssueView> {
    run_json_command(
        "acli",
        &["jira", "workitem", "view", ticket, "--json"],
        None,
    )
}

fn load_issue_comments(ticket: &str) -> Result<Vec<JiraComment>> {
    let limit = MAX_SPIKE_CONTEXT_COMMENTS.to_string();
    let response: JiraCommentList = run_json_command(
        "acli",
        &[
            "jira",
            "workitem",
            "comment",
            "list",
            "--key",
            ticket,
            "--json",
            "--limit",
            limit.as_str(),
            "--order",
            "-created",
        ],
        None,
    )?;
    Ok(response.comments)
}

fn prepare_cache_repo(
    layout: &StateLayout,
    repo_full_name: &str,
    job: &mut SpikeJob,
) -> Result<PathBuf> {
    let (owner, repo) = split_repo_name(repo_full_name)?;
    let repo_path = layout.repos_dir().join(owner).join(repo);
    if !repo_path.exists() {
        if let Some(parent) = repo_path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }
        run_command(
            "gh",
            &[
                "repo",
                "clone",
                repo_full_name,
                repo_path.to_string_lossy().as_ref(),
                "--",
                "--quiet",
            ],
            None,
            None,
        )?;
    }

    job.current_step = "updating_main".to_string();
    job.updated_at = super::now_utc();
    write_spike_job(layout, job)?;

    run_command(
        "git",
        &["fetch", "--all", "--prune"],
        Some(&repo_path),
        None,
    )?;
    run_command(
        "git",
        &["checkout", DEFAULT_BASE_BRANCH],
        Some(&repo_path),
        None,
    )?;
    run_command(
        "git",
        &["pull", "--ff-only", "origin", DEFAULT_BASE_BRANCH],
        Some(&repo_path),
        None,
    )?;
    Ok(repo_path)
}

fn create_spike_worktree(
    layout: &StateLayout,
    cache_repo_path: &Path,
    default_branch: &str,
    branch: &str,
) -> Result<PathBuf> {
    let worktree_path = layout.spikes_dir().join("worktrees").join(format!(
        "{}-{}",
        branch.replace('/', "_"),
        &Uuid::new_v4().simple().to_string()[..8]
    ));
    if let Some(parent) = worktree_path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }

    if local_branch_exists(cache_repo_path, branch)? {
        run_command(
            "git",
            &["branch", "-D", branch],
            Some(cache_repo_path),
            None,
        )?;
    }

    run_command(
        "git",
        &[
            "worktree",
            "add",
            "-b",
            branch,
            worktree_path.to_string_lossy().as_ref(),
            default_branch,
        ],
        Some(cache_repo_path),
        None,
    )?;
    Ok(worktree_path)
}

fn local_branch_exists(cache_repo_path: &Path, branch: &str) -> Result<bool> {
    let output = run_command(
        "git",
        &["branch", "--list", branch],
        Some(cache_repo_path),
        None,
    )?;
    Ok(!output.trim().is_empty())
}

fn run_codex_spike(
    issue: &JiraIssueView,
    existing_comments: &[JiraComment],
    branch: &str,
    repo_full_name: &str,
    worktree_path: &Path,
) -> Result<CodexSpikeExecResult> {
    let prompt = build_spike_prompt(issue, existing_comments, branch, repo_full_name);
    let output_path = worktree_path.join(SPIKE_OUTPUT_FILE);

    let mut child = Command::new("codex")
        .current_dir(worktree_path)
        .env("NO_COLOR", "1")
        .arg("exec")
        .arg("--json")
        .arg("--full-auto")
        .arg("--output-last-message")
        .arg(&output_path)
        .arg("-")
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("failed to launch codex exec")?;

    if let Some(mut stdin) = child.stdin.take() {
        stdin
            .write_all(prompt.as_bytes())
            .context("failed to write spike prompt to codex exec")?;
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

    let final_message = fs::read_to_string(&output_path)
        .with_context(|| format!("failed to read {}", output_path.display()))?;
    let _ = fs::remove_file(&output_path);
    parse_codex_spike_result(&final_message)
}

fn build_spike_prompt(
    issue: &JiraIssueView,
    existing_comments: &[JiraComment],
    branch: &str,
    repo_full_name: &str,
) -> String {
    let description = issue
        .fields
        .description
        .as_ref()
        .map(description_text)
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "No additional Jira description was provided.".to_string());
    let existing_comments_text = existing_comments_text(existing_comments);

    format!(
        "You are running a Jira spike for ticket {ticket} in repository {repo}.\n\nTicket summary:\n{summary}\n\nTicket description:\n{description}\n\nExisting Jira comments:\n{existing_comments}\n\nRequirements:\n- Use the already checked out branch `{branch}` only for local investigation.\n- The repository cache has already been updated and this worktree already starts from the latest `{default_branch}`.\n- Do not commit, push, or open a pull request.\n- Investigate requirements, existing implementations, likely touched files, gaps, risks, and a concrete implementation plan.\n- Use the existing Jira description and comments to avoid repeating information that is already captured there.\n- Only propose a Jira follow-up comment when you have materially new information, a sharper plan, uncovered risk, or concrete implementation guidance that is not already covered.\n- If there is no materially new information to add, set `comment` to null.\n- When `comment` is not null, write plain text that is easy to format into Jira sections and lists: short paragraphs, `- ` bullets, and `1. ` numbered steps are preferred.\n- Final response must be JSON only with this shape: {{\"summary\":\"<concise spike summary>\",\"comment\":\"<jira comment to post or null>\"}}\n\nJira issue URL: {issue_url}\n",
        ticket = issue.key,
        repo = repo_full_name,
        summary = issue.fields.summary,
        description = description,
        existing_comments = existing_comments_text,
        branch = branch,
        default_branch = DEFAULT_BASE_BRANCH,
        issue_url = task::issue_url(&issue.key),
    )
}

fn existing_comments_text(comments: &[JiraComment]) -> String {
    let rendered = comments
        .iter()
        .filter_map(|comment| {
            let body = description_text(&comment.body);
            let body = truncate_text(body.trim(), MAX_SPIKE_COMMENT_CHARS);
            if body.is_empty() {
                None
            } else {
                Some(format!("- {}: {}", comment.author, body))
            }
        })
        .collect::<Vec<_>>();

    if rendered.is_empty() {
        "No existing Jira comments were found.".to_string()
    } else {
        rendered.join("\n")
    }
}

fn description_text(value: &Value) -> String {
    if value.is_null() {
        return String::new();
    }
    if let Some(text) = value.as_str() {
        return text.to_string();
    }
    serde_json::to_string_pretty(value).unwrap_or_else(|_| value.to_string())
}

fn truncate_text(value: &str, max_chars: usize) -> String {
    let mut chars = value.chars();
    let truncated: String = chars.by_ref().take(max_chars).collect();
    if chars.next().is_some() {
        format!("{truncated}...")
    } else {
        truncated
    }
}

fn parse_codex_spike_result(text: &str) -> Result<CodexSpikeExecResult> {
    if let Ok(result) = serde_json::from_str::<CodexSpikeExecResult>(text.trim()) {
        return Ok(result);
    }

    let start = text
        .find('{')
        .context("codex spike output did not contain JSON")?;
    let end = text
        .rfind('}')
        .context("codex spike output did not contain JSON")?;
    serde_json::from_str::<CodexSpikeExecResult>(&text[start..=end])
        .context("failed to parse codex spike result JSON")
}

fn write_spike_job(layout: &StateLayout, job: &SpikeJob) -> Result<()> {
    let path = spike_job_path(layout, &job.id);
    let payload = serde_json::to_string_pretty(job).context("failed to serialize spike job")?;
    fs::write(&path, payload).with_context(|| format!("failed to write {}", path.display()))
}

fn spike_job_path(layout: &StateLayout, job_id: &str) -> PathBuf {
    layout.spikes_dir().join(format!("{job_id}.json"))
}

fn post_spike_comment(ticket: &str, comment: &str) -> Result<()> {
    let comment_path =
        std::env::temp_dir().join(format!("codex-spike-comment-{}.json", Uuid::new_v4()));
    let payload = serde_json::to_vec_pretty(&adf_comment_body(comment))
        .context("failed to serialize Jira spike comment")?;
    fs::write(&comment_path, payload)
        .with_context(|| format!("failed to write {}", comment_path.display()))?;

    let comment_path_string = comment_path.to_string_lossy().to_string();
    let result = run_command(
        "acli",
        &[
            "jira",
            "workitem",
            "comment",
            "create",
            "--key",
            ticket,
            "--body-file",
            &comment_path_string,
        ],
        None,
        None,
    );
    let _ = fs::remove_file(&comment_path);
    result.map(|_| ())
}

fn adf_comment_body(comment: &str) -> Value {
    let content = adf_comment_content(comment);
    json!({
        "version": 1,
        "type": "doc",
        "content": content
    })
}

fn adf_comment_content(comment: &str) -> Vec<Value> {
    let lines = comment.lines().map(str::trim_end).collect::<Vec<_>>();
    let mut content = Vec::new();
    let mut index = 0usize;

    while index < lines.len() {
        let line = lines[index].trim();
        if line.is_empty() {
            index += 1;
            continue;
        }

        if parse_bullet_line(line).is_some() {
            let mut items = Vec::new();
            while index < lines.len() {
                let current = lines[index].trim();
                if current.is_empty() {
                    break;
                }
                if let Some(text) = parse_bullet_line(current) {
                    items.push(adf_list_item(text));
                    index += 1;
                    continue;
                }
                break;
            }
            content.push(json!({
                "type": "bulletList",
                "content": items,
            }));
            continue;
        }

        if parse_ordered_line(line).is_some() {
            let mut items = Vec::new();
            while index < lines.len() {
                let current = lines[index].trim();
                if current.is_empty() {
                    break;
                }
                if let Some(text) = parse_ordered_line(current) {
                    items.push(adf_list_item(text));
                    index += 1;
                    continue;
                }
                break;
            }
            content.push(json!({
                "type": "orderedList",
                "content": items,
            }));
            continue;
        }

        let mut paragraph_lines = Vec::new();
        while index < lines.len() {
            let current = lines[index].trim();
            if current.is_empty() {
                break;
            }
            if parse_bullet_line(current).is_some() || parse_ordered_line(current).is_some() {
                break;
            }
            paragraph_lines.push(current.to_string());
            index += 1;
        }
        let paragraph_text = paragraph_lines.join(" ");
        if !paragraph_text.is_empty() {
            content.push(adf_paragraph(&paragraph_text));
        }
    }

    if content.is_empty() {
        vec![adf_paragraph(comment.trim())]
    } else {
        content
    }
}

fn adf_paragraph(text: &str) -> Value {
    json!({
        "type": "paragraph",
        "content": [{
            "type": "text",
            "text": text
        }]
    })
}

fn adf_list_item(text: &str) -> Value {
    json!({
        "type": "listItem",
        "content": [adf_paragraph(text)]
    })
}

fn parse_bullet_line(line: &str) -> Option<&str> {
    line.strip_prefix("- ")
        .or_else(|| line.strip_prefix("* "))
        .map(str::trim)
        .filter(|value| !value.is_empty())
}

fn parse_ordered_line(line: &str) -> Option<&str> {
    let (prefix, rest) = line.split_once(". ")?;
    if prefix.chars().all(|character| character.is_ascii_digit()) {
        let trimmed = rest.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed)
        }
    } else {
        None
    }
}

fn run_json_command<T: for<'de> Deserialize<'de>>(
    program: &str,
    args: &[&str],
    cwd: Option<&Path>,
) -> Result<T> {
    let output = run_command(program, args, cwd, None)?;
    serde_json::from_str(&output).with_context(|| {
        format!(
            "failed to parse JSON from `{}`",
            command_preview(program, args)
        )
    })
}

fn run_command(
    program: &str,
    args: &[&str],
    cwd: Option<&Path>,
    stdin: Option<&str>,
) -> Result<String> {
    let mut command = Command::new(program);
    command.args(args);
    if let Some(cwd) = cwd {
        command.current_dir(cwd);
    }
    if stdin.is_some() {
        command.stdin(Stdio::piped());
    }
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());

    let mut child = command
        .spawn()
        .with_context(|| format!("failed to start `{}`", command_preview(program, args)))?;

    if let Some(input) = stdin {
        let handle = child.stdin.as_mut().context("failed to access stdin")?;
        handle.write_all(input.as_bytes()).with_context(|| {
            format!(
                "failed to write stdin for `{}`",
                command_preview(program, args)
            )
        })?;
    }

    let output = child
        .wait_with_output()
        .with_context(|| format!("failed to wait for `{}`", command_preview(program, args)))?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    if !output.status.success() {
        let message = if stderr.is_empty() {
            format!(
                "{} failed with status {}",
                command_preview(program, args),
                output.status
            )
        } else {
            format!("{}: {}", command_preview(program, args), stderr)
        };
        bail!(message);
    }

    Ok(stdout)
}

fn command_preview(program: &str, args: &[&str]) -> String {
    std::iter::once(program)
        .chain(args.iter().copied())
        .collect::<Vec<_>>()
        .join(" ")
}

fn split_repo_name(repo_full_name: &str) -> Result<(&str, &str)> {
    repo_full_name
        .split_once('/')
        .context("invalid repo full name")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_codex_spike_result_supports_null_comment() {
        let result = parse_codex_spike_result(r#"{"summary":"done","comment":null}"#).unwrap();
        assert_eq!(result.summary, "done");
        assert_eq!(result.comment, None);
    }

    #[test]
    fn existing_comments_text_handles_empty_comments() {
        assert_eq!(
            existing_comments_text(&[]),
            "No existing Jira comments were found."
        );
    }

    #[test]
    fn adf_comment_content_preserves_paragraphs_and_lists() {
        let content = adf_comment_content(
            "Context paragraph.\n\n- First bullet\n- Second bullet\n\n1. First step\n2. Second step",
        );
        assert_eq!(content.len(), 3);
        assert_eq!(content[0]["type"], "paragraph");
        assert_eq!(content[1]["type"], "bulletList");
        assert_eq!(content[2]["type"], "orderedList");
    }
}
