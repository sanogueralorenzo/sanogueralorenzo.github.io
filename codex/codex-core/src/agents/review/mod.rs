mod comments;
mod github;
mod jobs;
mod workspace;

use super::ReviewPublishMode;
use super::StateLayout;
use super::ensure_state_layout;
use super::load_agents_config;
use anyhow::{Context, Result, bail};
use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};

use comments::post_review_comments;
use github::ExistingReviewFeedback;
use github::fetch_existing_review_feedback;
use github::fetch_pull_request_view;
use github::list_pull_requests_with_config;
use github::review_pull_request_label;
use jobs::ReviewJobStore;
use jobs::into_review_job_output;
use jobs::list_review_jobs_data;
use jobs::load_review_job_data;
use jobs::run_review_step;
use workspace::build_base_branch_review_request;
use workspace::checkout_pull_request;
use workspace::load_upstream_review_prompts;
use workspace::resolve_merge_base;
use workspace::run_codex_exec_review;

#[derive(Subcommand, Debug)]
pub enum ReviewCommand {
    /// List open pull requests across your repos and orgs
    List(ReviewListArgs),
    /// Review one pull request and publish or draft findings on GitHub
    Run(ReviewRunArgs),
    /// List persisted review jobs
    Jobs(ReviewJobsArgs),
    /// Show one persisted review job
    Show(ReviewShowArgs),
}

#[derive(Args, Debug)]
pub struct ReviewListArgs {
    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct ReviewRunArgs {
    /// Pull request URL or OWNER/REPO#NUMBER
    pub pull_request: String,

    /// Override the configured review publish mode
    #[arg(long = "publish-mode")]
    pub publish_mode: Option<ReviewPublishMode>,

    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct ReviewJobsArgs {
    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Args, Debug)]
pub struct ReviewShowArgs {
    pub review_id: String,

    #[arg(long)]
    pub json: bool,

    #[arg(long)]
    pub plain: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewPullRequest {
    pub owner: String,
    pub repo: String,
    pub number: u64,
    pub title: String,
    pub url: String,
    pub created_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ReviewRunResult {
    pub review_id: String,
    pub publish_mode: ReviewPublishMode,
    pub owner: String,
    pub repo: String,
    pub number: u64,
    pub url: String,
    pub posted_comments: usize,
    pub failed_comments: usize,
    pub failed_comment_details: Vec<ReviewCommentFailure>,
    pub summary: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewCommentFailure {
    pub title: String,
    pub path: Option<String>,
    pub start_line: u32,
    pub end_line: u32,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ReviewJobStatus {
    Queued,
    Running,
    PostingComments,
    Completed,
    Failed,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum ReviewMenuState {
    Published,
    NeedsAttention,
    InProgress,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewJobSnapshot {
    pub id: String,
    pub pull_request: String,
    pub owner: String,
    pub repo: String,
    pub number: u64,
    pub url: Option<String>,
    pub status: ReviewJobStatus,
    pub current_step: String,
    pub created_at: String,
    pub started_at: Option<String>,
    pub finished_at: Option<String>,
    pub posted_comments: usize,
    pub failed_comments: usize,
    pub failed_comment_details: Vec<ReviewCommentFailure>,
    pub summary: Option<String>,
    pub error: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewJobOutput {
    pub id: String,
    pub pull_request: String,
    pub owner: String,
    pub repo: String,
    pub number: u64,
    pub url: Option<String>,
    pub status: ReviewMenuState,
    pub current_step: String,
    pub created_at: String,
    pub started_at: Option<String>,
    pub finished_at: Option<String>,
    pub posted_comments: usize,
    pub failed_comments: usize,
    pub failed_comment_details: Vec<ReviewCommentFailure>,
    pub summary: Option<String>,
    pub error: Option<String>,
}

#[derive(Debug, Clone)]
pub(super) struct PullRequestReference {
    pub owner: String,
    pub repo: String,
    pub number: u64,
}

impl PullRequestReference {
    pub(super) fn repo_name_with_owner(&self) -> String {
        format!("{}/{}", self.owner, self.repo)
    }
}

pub fn handle_review(action: ReviewCommand, layout: &StateLayout) -> Result<()> {
    ensure_state_layout(layout)?;
    match action {
        ReviewCommand::List(args) => list_pull_requests(layout, args),
        ReviewCommand::Run(args) => run_review(layout, args),
        ReviewCommand::Jobs(args) => list_review_jobs(layout, args),
        ReviewCommand::Show(args) => show_review_job(layout, args),
    }
}

fn list_pull_requests(layout: &StateLayout, args: ReviewListArgs) -> Result<()> {
    let config = load_agents_config(layout)?;
    let pull_requests = list_pull_requests_with_config(&config)?;

    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&pull_requests).context("failed to serialize PR list")?
        );
        return Ok(());
    }

    if args.plain {
        for pull_request in pull_requests {
            println!("{}", review_pull_request_label(&pull_request));
        }
        return Ok(());
    }

    if pull_requests.is_empty() {
        println!("No open pull requests found.");
        return Ok(());
    }

    for pull_request in pull_requests {
        println!("{}", review_pull_request_label(&pull_request));
    }

    Ok(())
}

fn run_review(layout: &StateLayout, args: ReviewRunArgs) -> Result<()> {
    let pr_ref = parse_pull_request_reference(&args.pull_request)?;
    let config = load_agents_config(layout)?;
    let publish_mode = args.publish_mode.unwrap_or(config.review_mode);
    let mut job = ReviewJobStore::create(layout, &args.pull_request, &pr_ref)?;

    let pull_request = run_review_step(
        &mut job,
        ReviewJobStatus::Running,
        "fetching_pr",
        "Loading pull request metadata.",
        || fetch_pull_request_view(&pr_ref),
    )?;
    job.set_pull_request_url(&pull_request.url)?;

    let workspace = run_review_step(
        &mut job,
        ReviewJobStatus::Running,
        "preparing_repo",
        "Preparing cached repo and review worktree.",
        || checkout_pull_request(layout, &pr_ref, &pull_request),
    )?;

    let existing_feedback = run_review_step(
        &mut job,
        ReviewJobStatus::Running,
        "loading_existing_feedback",
        "Loading existing PR comments and review summaries.",
        || fetch_existing_review_feedback(&pr_ref),
    )?;

    let upstream_prompts = run_review_step(
        &mut job,
        ReviewJobStatus::Running,
        "loading_prompts",
        "Fetching upstream review prompts.",
        load_upstream_review_prompts,
    )?;

    let merge_base = run_review_step(
        &mut job,
        ReviewJobStatus::Running,
        "resolving_merge_base",
        "Resolving merge base against the PR base branch.",
        || resolve_merge_base(&workspace.repo_dir, &pull_request.base_ref_name),
    )?;

    let review_request = build_base_branch_review_request(
        &upstream_prompts,
        &pull_request.base_ref_name,
        merge_base.as_deref(),
    );
    let prompt = format!(
        "{}\n\n{}\n\n{}\n\n{}",
        upstream_prompts.review_rubric,
        review_request,
        existing_feedback_prompt(&existing_feedback),
        "Formatting:\n- When mentioning files, classes, methods, or variables, use `$reference`."
    );
    let review = run_review_step(
        &mut job,
        ReviewJobStatus::Running,
        "running_codex_exec",
        "Running codex exec review.",
        || run_codex_exec_review(&workspace.repo_dir, &prompt),
    )?;

    let changed_lines = run_review_step(
        &mut job,
        ReviewJobStatus::Running,
        "collecting_diff",
        "Collecting changed diff lines for PR comment validation.",
        || comments::collect_changed_diff_lines(&workspace.repo_dir, &pull_request.base_ref_name),
    )?;

    let mut result = run_review_step(
        &mut job,
        ReviewJobStatus::PostingComments,
        "posting_comments",
        "Publishing review findings to GitHub.",
        || {
            post_review_comments(
                &pr_ref,
                &workspace.repo_dir,
                &pull_request,
                review,
                &changed_lines,
                publish_mode,
            )
        },
    )?;
    result.review_id = job.snapshot.id.clone();

    let completion_step =
        if result.publish_mode == ReviewPublishMode::Pending && result.posted_comments > 0 {
            "pending_review_created"
        } else {
            "completed"
        };
    job.complete(&result, completion_step)?;

    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&result).context("failed to serialize review result")?
        );
        return Ok(());
    }

    if args.plain {
        println!(
            "{} {} {} {}",
            result.review_id, result.url, result.posted_comments, result.failed_comments
        );
        return Ok(());
    }

    println!("Reviewed {}", result.url);
    println!("Review ID: {}", result.review_id);
    println!("Publish mode: {}", result.publish_mode.as_str());
    println!("Posted comments: {}", result.posted_comments);
    println!("Failed comments: {}", result.failed_comments);
    if !result.failed_comment_details.is_empty() {
        println!("Failure reasons:");
        for failure in &result.failed_comment_details {
            let path = failure.path.as_deref().unwrap_or("<unknown>");
            println!(
                "- {} ({}:{}-{}): {}",
                failure.title, path, failure.start_line, failure.end_line, failure.reason
            );
        }
    }
    println!("Summary: {}", result.summary);
    Ok(())
}

fn existing_feedback_prompt(feedback: &[ExistingReviewFeedback]) -> String {
    if feedback.is_empty() {
        return "Existing PR comments:\nNo existing PR comments were found.\n\nAvoid repeating feedback that is already present on the pull request.".to_string();
    }

    let rendered = feedback
        .iter()
        .take(20)
        .map(|entry| format!("- {}", truncate_review_feedback(&entry.body, 600)))
        .collect::<Vec<_>>()
        .join("\n");

    format!(
        "Existing PR comments:\n{}\n\nAvoid repeating feedback that is already present on the pull request unless you are correcting it or adding materially new information.",
        rendered
    )
}

fn truncate_review_feedback(value: &str, max_chars: usize) -> String {
    let mut chars = value.chars();
    let truncated: String = chars.by_ref().take(max_chars).collect();
    if chars.next().is_some() {
        format!("{truncated}...")
    } else {
        truncated
    }
}

fn list_review_jobs(layout: &StateLayout, args: ReviewJobsArgs) -> Result<()> {
    let jobs = list_review_jobs_data(layout)?;
    let output_jobs: Vec<ReviewJobOutput> = jobs.into_iter().map(into_review_job_output).collect();

    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&output_jobs)
                .context("failed to serialize review jobs")?
        );
        return Ok(());
    }

    if args.plain {
        for job in output_jobs {
            println!(
                "{} {} {}",
                job.id,
                jobs::review_menu_state_label(&job.status),
                job.pull_request
            );
        }
        return Ok(());
    }

    if output_jobs.is_empty() {
        println!("No review jobs found.");
        return Ok(());
    }

    for job in output_jobs {
        println!(
            "{} {:<16} {}",
            job.id,
            jobs::review_menu_state_label(&job.status),
            jobs::review_job_output_summary_label(&job)
        );
    }

    Ok(())
}

fn show_review_job(layout: &StateLayout, args: ReviewShowArgs) -> Result<()> {
    let output_job = into_review_job_output(load_review_job_data(layout, &args.review_id)?);

    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&output_job).context("failed to serialize review job")?
        );
        return Ok(());
    }

    if args.plain {
        println!(
            "{} {}",
            output_job.id,
            jobs::review_menu_state_label(&output_job.status)
        );
        return Ok(());
    }

    println!("id: {}", output_job.id);
    println!(
        "status: {}",
        jobs::review_menu_state_label(&output_job.status)
    );
    println!("current_step: {}", output_job.current_step);
    println!("pull_request: {}", output_job.pull_request);
    println!("owner: {}", output_job.owner);
    println!("repo: {}", output_job.repo);
    println!("number: {}", output_job.number);
    if let Some(url) = &output_job.url {
        println!("url: {}", url);
    }
    println!("created_at: {}", output_job.created_at);
    if let Some(started_at) = &output_job.started_at {
        println!("started_at: {}", started_at);
    }
    if let Some(finished_at) = &output_job.finished_at {
        println!("finished_at: {}", finished_at);
    }
    println!("posted_comments: {}", output_job.posted_comments);
    println!("failed_comments: {}", output_job.failed_comments);
    if let Some(summary) = &output_job.summary {
        println!("summary: {}", summary);
    }
    if let Some(error) = &output_job.error {
        println!("error: {}", error);
    }
    if !output_job.failed_comment_details.is_empty() {
        println!("failed_comment_details:");
        for failure in &output_job.failed_comment_details {
            let path = failure.path.as_deref().unwrap_or("<unknown>");
            println!(
                "- {} ({}:{}-{}): {}",
                failure.title, path, failure.start_line, failure.end_line, failure.reason
            );
        }
    }

    Ok(())
}

fn parse_pull_request_reference(raw: &str) -> Result<PullRequestReference> {
    if let Some(reference) = parse_pull_request_url(raw)? {
        return Ok(reference);
    }

    let (repo_name, number) = raw
        .trim()
        .rsplit_once('#')
        .with_context(|| format!("invalid pull request reference: {raw}"))?;
    let (owner, repo) = repo_name
        .split_once('/')
        .with_context(|| format!("invalid pull request reference: {raw}"))?;

    Ok(PullRequestReference {
        owner: owner.to_string(),
        repo: repo.to_string(),
        number: number
            .parse::<u64>()
            .with_context(|| format!("invalid pull request number: {number}"))?,
    })
}

fn parse_pull_request_url(raw: &str) -> Result<Option<PullRequestReference>> {
    let url = match raw.trim().strip_prefix("https://github.com/") {
        Some(url) => url,
        None => return Ok(None),
    };

    let parts: Vec<&str> = url.split('/').collect();
    if parts.len() < 4 || parts[2] != "pull" {
        bail!("invalid GitHub pull request URL: {raw}");
    }

    Ok(Some(PullRequestReference {
        owner: parts[0].to_string(),
        repo: parts[1].to_string(),
        number: parts[3]
            .parse::<u64>()
            .with_context(|| format!("invalid pull request number in URL: {}", parts[3]))?,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_pull_request_url() {
        let reference =
            parse_pull_request_reference("https://github.com/openai/codex/pull/123").unwrap();
        assert_eq!(reference.owner, "openai");
        assert_eq!(reference.repo, "codex");
        assert_eq!(reference.number, 123);
    }

    #[test]
    fn parses_owner_repo_number_reference() {
        let reference = parse_pull_request_reference("openai/codex#123").unwrap();
        assert_eq!(reference.owner, "openai");
        assert_eq!(reference.repo, "codex");
        assert_eq!(reference.number, 123);
    }

    #[test]
    fn rejects_invalid_pull_request_reference() {
        assert!(parse_pull_request_reference("not-a-pr").is_err());
    }
}
