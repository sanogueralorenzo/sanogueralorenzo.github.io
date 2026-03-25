use super::AgentsConfig;
use super::StateLayout;
use super::ensure_state_layout;
use super::load_agents_config;
use super::now_utc;
use crate::core::temp::temp_file_path;
use anyhow::{Context, Result, bail};
use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::collections::HashSet;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use uuid::Uuid;

const VIEWER_QUERY: &str = r#"
query {
  viewer {
    login
    organizations(first: 100) {
      nodes { login }
    }
  }
}
"#;

const SEARCH_QUERY: &str = r#"
query($searchQuery: String!, $endCursor: String) {
  search(query: $searchQuery, type: ISSUE, first: 100, after: $endCursor) {
    nodes {
      ... on PullRequest {
        number
        title
        url
        createdAt
        repository {
          name
          nameWithOwner
          owner { login }
        }
      }
    }
    pageInfo {
      hasNextPage
      endCursor
    }
  }
}
"#;

#[derive(Subcommand, Debug)]
pub enum ReviewCommand {
    /// List open pull requests across your repos and orgs
    List(ReviewListArgs),
    /// Review one pull request and publish findings to GitHub
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

#[derive(Debug, Clone, Serialize, Deserialize)]
struct ReviewJobEvent {
    timestamp: String,
    kind: String,
    step: String,
    message: String,
}

#[derive(Debug, Clone)]
enum ReviewOwner {
    User(String),
    Org(String),
}

#[derive(Debug, Deserialize)]
struct ViewerResponse {
    data: ViewerData,
}

#[derive(Debug, Deserialize)]
struct ViewerData {
    viewer: Viewer,
}

#[derive(Debug, Deserialize)]
struct Viewer {
    login: String,
    organizations: OrganizationConnection,
}

#[derive(Debug, Deserialize)]
struct OrganizationConnection {
    nodes: Vec<LoginNode>,
}

#[derive(Debug, Deserialize)]
struct LoginNode {
    login: String,
}

#[derive(Debug, Deserialize)]
struct SearchPage {
    data: SearchData,
}

#[derive(Debug, Deserialize)]
struct SearchData {
    search: SearchConnection,
}

#[derive(Debug, Deserialize)]
struct SearchConnection {
    nodes: Vec<Option<SearchPullRequest>>,
}

#[derive(Debug, Deserialize)]
struct SearchPullRequest {
    number: u64,
    title: String,
    url: String,
    #[serde(rename = "createdAt")]
    created_at: String,
    repository: SearchRepository,
}

#[derive(Debug, Deserialize)]
struct SearchRepository {
    name: String,
    owner: LoginNode,
}

#[derive(Debug, Deserialize)]
struct PullRequestView {
    number: u64,
    url: String,
    #[serde(rename = "baseRefName")]
    base_ref_name: String,
    #[serde(rename = "headRefOid")]
    head_ref_oid: String,
}

struct ReviewWorkspace {
    cache_repo_dir: PathBuf,
    repo_dir: PathBuf,
}

struct ReviewJobStore {
    snapshot: ReviewJobSnapshot,
    job_path: PathBuf,
    events_path: PathBuf,
}

#[derive(Debug, Deserialize)]
struct ReviewOutputEvent {
    findings: Vec<ReviewFinding>,
    overall_correctness: String,
    overall_explanation: String,
}

#[derive(Debug, Deserialize)]
struct ReviewFinding {
    title: String,
    body: String,
    confidence_score: f32,
    priority: Option<i32>,
    code_location: ReviewCodeLocation,
}

#[derive(Debug, Deserialize)]
struct ReviewCodeLocation {
    absolute_file_path: PathBuf,
    line_range: ReviewLineRange,
}

#[derive(Debug, Deserialize)]
struct ReviewLineRange {
    start: u32,
    end: u32,
}

struct UpstreamReviewPrompts {
    review_rubric: String,
    base_branch_prompt: String,
    base_branch_prompt_backup: String,
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
    let pull_requests = load_open_pull_requests(&config)?;

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
    let mut job = ReviewJobStore::create(layout, &args.pull_request, &pr_ref)?;

    let pull_request = match run_review_step(
        &mut job,
        ReviewJobStatus::Running,
        "fetching_pr",
        "Loading pull request metadata.",
        || fetch_pull_request_view(&pr_ref),
    ) {
        Ok(pull_request) => pull_request,
        Err(error) => return Err(error),
    };
    job.set_pull_request_url(&pull_request.url)?;

    let workspace = match run_review_step(
        &mut job,
        ReviewJobStatus::Running,
        "preparing_repo",
        "Preparing cached repo and review worktree.",
        || checkout_pull_request(layout, &pr_ref, &pull_request),
    ) {
        Ok(workspace) => workspace,
        Err(error) => return Err(error),
    };

    let upstream_prompts = match run_review_step(
        &mut job,
        ReviewJobStatus::Running,
        "loading_prompts",
        "Fetching upstream review prompts.",
        load_upstream_review_prompts,
    ) {
        Ok(prompts) => prompts,
        Err(error) => return Err(error),
    };

    let merge_base = match run_review_step(
        &mut job,
        ReviewJobStatus::Running,
        "resolving_merge_base",
        "Resolving merge base against the PR base branch.",
        || resolve_merge_base(&workspace.repo_dir, &pull_request.base_ref_name),
    ) {
        Ok(merge_base) => merge_base,
        Err(error) => return Err(error),
    };

    let review_request = build_base_branch_review_request(
        &upstream_prompts,
        &pull_request.base_ref_name,
        merge_base.as_deref(),
    );
    let prompt = format!("{}\n\n{}", upstream_prompts.review_rubric, review_request);
    let review = match run_review_step(
        &mut job,
        ReviewJobStatus::Running,
        "running_codex_exec",
        "Running codex exec review.",
        || run_codex_exec_review(&workspace.repo_dir, &prompt),
    ) {
        Ok(review) => review,
        Err(error) => return Err(error),
    };

    let changed_lines = match run_review_step(
        &mut job,
        ReviewJobStatus::Running,
        "collecting_diff",
        "Collecting changed diff lines for PR comment validation.",
        || collect_changed_diff_lines(&workspace.repo_dir, &pull_request.base_ref_name),
    ) {
        Ok(changed_lines) => changed_lines,
        Err(error) => return Err(error),
    };

    let mut result = match run_review_step(
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
            )
        },
    ) {
        Ok(result) => result,
        Err(error) => return Err(error),
    };
    result.review_id = job.snapshot.id.clone();
    job.complete(&result)?;

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

fn list_review_jobs(layout: &StateLayout, args: ReviewJobsArgs) -> Result<()> {
    let jobs = load_review_jobs(layout)?;
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
                review_menu_state_label(&job.status),
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
            review_menu_state_label(&job.status),
            review_job_output_summary_label(&job)
        );
    }

    Ok(())
}

fn show_review_job(layout: &StateLayout, args: ReviewShowArgs) -> Result<()> {
    let output_job = into_review_job_output(load_review_job(layout, &args.review_id)?);

    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&output_job).context("failed to serialize review job")?
        );
        return Ok(());
    }

    if args.plain {
        println!("{} {}", output_job.id, review_menu_state_label(&output_job.status));
        return Ok(());
    }

    println!("id: {}", output_job.id);
    println!("status: {}", review_menu_state_label(&output_job.status));
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

fn into_review_job_output(job: ReviewJobSnapshot) -> ReviewJobOutput {
    let status = derive_review_menu_state(&job);
    ReviewJobOutput {
        id: job.id,
        pull_request: job.pull_request,
        owner: job.owner,
        repo: job.repo,
        number: job.number,
        url: job.url,
        status,
        current_step: job.current_step,
        created_at: job.created_at,
        started_at: job.started_at,
        finished_at: job.finished_at,
        posted_comments: job.posted_comments,
        failed_comments: job.failed_comments,
        failed_comment_details: job.failed_comment_details,
        summary: job.summary,
        error: job.error,
    }
}

fn run_review_step<T, F>(
    job: &mut ReviewJobStore,
    status: ReviewJobStatus,
    step: &str,
    message: &str,
    operation: F,
) -> Result<T>
where
    F: FnOnce() -> Result<T>,
{
    job.set_status(status, step, message)?;
    match operation() {
        Ok(value) => Ok(value),
        Err(error) => {
            job.fail(step, &error)?;
            Err(error)
        }
    }
}

impl ReviewJobStore {
    fn create(
        layout: &StateLayout,
        pull_request: &str,
        pr_ref: &PullRequestReference,
    ) -> Result<Self> {
        let id = Uuid::new_v4().to_string();
        let review_dir = layout.root.join("reviews").join(&id);
        fs::create_dir_all(&review_dir)
            .with_context(|| format!("failed to create {}", review_dir.display()))?;

        let snapshot = ReviewJobSnapshot {
            id,
            pull_request: pull_request.to_string(),
            owner: pr_ref.owner.clone(),
            repo: pr_ref.repo.clone(),
            number: pr_ref.number,
            url: None,
            status: ReviewJobStatus::Queued,
            current_step: "queued".to_string(),
            created_at: now_utc(),
            started_at: None,
            finished_at: None,
            posted_comments: 0,
            failed_comments: 0,
            failed_comment_details: Vec::new(),
            summary: None,
            error: None,
        };
        let job_path = review_dir.join("job.json");
        let events_path = review_dir.join("events.jsonl");
        let store = Self {
            snapshot,
            job_path,
            events_path,
        };
        store.write_snapshot()?;
        store.append_event("queued", "queued", "Review job created.")?;
        Ok(store)
    }

    fn set_pull_request_url(&mut self, url: &str) -> Result<()> {
        self.snapshot.url = Some(url.to_string());
        self.write_snapshot()
    }

    fn set_status(&mut self, status: ReviewJobStatus, step: &str, message: &str) -> Result<()> {
        if self.snapshot.started_at.is_none() && status != ReviewJobStatus::Queued {
            self.snapshot.started_at = Some(now_utc());
        }
        self.snapshot.status = status;
        self.snapshot.current_step = step.to_string();
        self.write_snapshot()?;
        self.append_event("step", step, message)
    }

    fn complete(&mut self, result: &ReviewRunResult) -> Result<()> {
        self.snapshot.status = ReviewJobStatus::Completed;
        self.snapshot.current_step = "completed".to_string();
        self.snapshot.finished_at = Some(now_utc());
        self.snapshot.posted_comments = result.posted_comments;
        self.snapshot.failed_comments = result.failed_comments;
        self.snapshot.failed_comment_details = result.failed_comment_details.clone();
        self.snapshot.summary = Some(result.summary.clone());
        self.snapshot.error = None;
        self.snapshot.url = Some(result.url.clone());
        self.write_snapshot()?;
        self.append_event("completed", "completed", "Review job completed.")
    }

    fn fail(&mut self, step: &str, error: &anyhow::Error) -> Result<()> {
        self.snapshot.status = ReviewJobStatus::Failed;
        self.snapshot.current_step = step.to_string();
        if self.snapshot.started_at.is_none() {
            self.snapshot.started_at = Some(now_utc());
        }
        self.snapshot.finished_at = Some(now_utc());
        self.snapshot.error = Some(error.to_string());
        self.write_snapshot()?;
        self.append_event("failed", step, &error.to_string())
    }

    fn write_snapshot(&self) -> Result<()> {
        let payload = serde_json::to_string_pretty(&self.snapshot)
            .context("failed to serialize review job snapshot")?;
        fs::write(&self.job_path, payload)
            .with_context(|| format!("failed to write {}", self.job_path.display()))
    }

    fn append_event(&self, kind: &str, step: &str, message: &str) -> Result<()> {
        let event = ReviewJobEvent {
            timestamp: now_utc(),
            kind: kind.to_string(),
            step: step.to_string(),
            message: message.to_string(),
        };
        let mut file = fs::OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.events_path)
            .with_context(|| format!("failed to open {}", self.events_path.display()))?;
        let payload =
            serde_json::to_string(&event).context("failed to serialize review job event")?;
        writeln!(file, "{payload}")
            .with_context(|| format!("failed to write {}", self.events_path.display()))
    }
}

fn load_review_jobs(layout: &StateLayout) -> Result<Vec<ReviewJobSnapshot>> {
    let reviews_dir = layout.root.join("reviews");
    if !reviews_dir.exists() {
        return Ok(Vec::new());
    }

    let mut jobs = Vec::new();
    for entry in fs::read_dir(&reviews_dir)
        .with_context(|| format!("failed to read {}", reviews_dir.display()))?
    {
        let entry = entry?;
        let path = entry.path();
        if !path.is_dir() {
            continue;
        }
        let job_path = path.join("job.json");
        if !job_path.exists() {
            continue;
        }
        jobs.push(load_review_job_snapshot(&job_path)?);
    }

    jobs.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    Ok(jobs)
}

fn load_review_job(layout: &StateLayout, review_id: &str) -> Result<ReviewJobSnapshot> {
    let review_id = review_id.trim();
    if review_id.is_empty() {
        bail!("Missing review job id");
    }
    let job_path = layout.root.join("reviews").join(review_id).join("job.json");
    if !job_path.exists() {
        bail!("Review job not found: {review_id}");
    }
    load_review_job_snapshot(&job_path)
}

fn load_review_job_snapshot(job_path: &Path) -> Result<ReviewJobSnapshot> {
    let content = fs::read_to_string(job_path)
        .with_context(|| format!("failed to read {}", job_path.display()))?;
    serde_json::from_str(&content)
        .with_context(|| format!("failed to parse {}", job_path.display()))
}

fn review_menu_state_label(menu_state: &ReviewMenuState) -> &'static str {
    match menu_state {
        ReviewMenuState::Published => "published",
        ReviewMenuState::NeedsAttention => "needs_attention",
        ReviewMenuState::InProgress => "in_progress",
    }
}

fn derive_review_menu_state(job: &ReviewJobSnapshot) -> ReviewMenuState {
    match job.status {
        ReviewJobStatus::Queued | ReviewJobStatus::Running | ReviewJobStatus::PostingComments => {
            ReviewMenuState::InProgress
        }
        ReviewJobStatus::Failed => ReviewMenuState::NeedsAttention,
        ReviewJobStatus::Completed => {
            if job.failed_comments > 0 || job.posted_comments == 0 {
                ReviewMenuState::NeedsAttention
            } else {
                ReviewMenuState::Published
            }
        }
    }
}

fn review_job_output_summary_label(job: &ReviewJobOutput) -> String {
    let base = format!("{}/{}#{}", job.owner, job.repo, job.number);
    match &job.summary {
        Some(summary) if !summary.trim().is_empty() => format!("{base} {summary}"),
        _ => base,
    }
}

fn load_open_pull_requests(config: &AgentsConfig) -> Result<Vec<ReviewPullRequest>> {
    let owners = load_review_owners()?;
    let mut seen = HashSet::new();
    let mut pull_requests = Vec::new();
    let allowed_repos: HashSet<&str> = config.allowed_repos.iter().map(String::as_str).collect();

    for owner in owners {
        for pull_request in search_open_pull_requests_for_owner(&owner)? {
            let full_name = format!("{}/{}", pull_request.owner, pull_request.repo);
            if !allowed_repos.is_empty() && !allowed_repos.contains(full_name.as_str()) {
                continue;
            }
            if seen.insert(pull_request.url.clone()) {
                pull_requests.push(pull_request);
            }
        }
    }

    pull_requests.sort_by(|a, b| b.created_at.cmp(&a.created_at));
    Ok(pull_requests)
}

fn load_review_owners() -> Result<Vec<ReviewOwner>> {
    let output = run_gh(
        vec![
            "api".to_string(),
            "graphql".to_string(),
            "-f".to_string(),
            format!("query={VIEWER_QUERY}"),
        ],
        None,
    )?;
    let response: ViewerResponse =
        serde_json::from_str(&output).context("failed to parse gh viewer response")?;

    let mut owners = vec![ReviewOwner::User(response.data.viewer.login)];
    owners.extend(
        response
            .data
            .viewer
            .organizations
            .nodes
            .into_iter()
            .map(|organization| ReviewOwner::Org(organization.login)),
    );
    Ok(owners)
}

fn search_open_pull_requests_for_owner(owner: &ReviewOwner) -> Result<Vec<ReviewPullRequest>> {
    let search_query = match owner {
        ReviewOwner::User(login) => format!("is:pr is:open archived:false user:{login}"),
        ReviewOwner::Org(login) => format!("is:pr is:open archived:false org:{login}"),
    };
    let output = run_gh(
        vec![
            "api".to_string(),
            "graphql".to_string(),
            "--paginate".to_string(),
            "--slurp".to_string(),
            "-f".to_string(),
            format!("query={SEARCH_QUERY}"),
            "-F".to_string(),
            format!("searchQuery={search_query}"),
        ],
        None,
    )?;
    let pages: Vec<SearchPage> =
        serde_json::from_str(&output).context("failed to parse gh search response")?;

    let mut pull_requests = Vec::new();
    for page in pages {
        for node in page.data.search.nodes.into_iter().flatten() {
            pull_requests.push(ReviewPullRequest {
                owner: node.repository.owner.login,
                repo: node.repository.name,
                number: node.number,
                title: node.title,
                url: node.url,
                created_at: node.created_at,
            });
        }
    }

    Ok(pull_requests)
}

fn fetch_pull_request_view(pr_ref: &PullRequestReference) -> Result<PullRequestView> {
    let output = run_gh(
        vec![
            "pr".to_string(),
            "view".to_string(),
            pr_ref.number.to_string(),
            "--repo".to_string(),
            pr_ref.repo_name_with_owner(),
            "--json".to_string(),
            "number,url,baseRefName,headRefOid".to_string(),
        ],
        None,
    )?;
    serde_json::from_str(&output).context("failed to parse gh pr view response")
}

fn checkout_pull_request(
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

fn load_upstream_review_prompts() -> Result<UpstreamReviewPrompts> {
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

fn extract_rust_string_constant(source: &str, constant_name: &str) -> Result<String> {
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

fn resolve_merge_base(repo_dir: &Path, base_ref_name: &str) -> Result<Option<String>> {
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

fn build_base_branch_review_request(
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

fn run_codex_exec_review(repo_dir: &Path, prompt: &str) -> Result<ReviewOutputEvent> {
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

#[derive(Debug, Default, Clone, PartialEq, Eq)]
struct FileDiffLines {
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

fn collect_changed_diff_lines(
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

fn post_review_comments(
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
        let normalized_path = normalize_comment_path(&finding.code_location.absolute_file_path, repo_dir).ok();
        let path_for_comment = normalized_path
            .clone()
            .unwrap_or_else(|| finding.code_location.absolute_file_path.display().to_string());

        let body = render_inline_comment_body(finding);
        let inline_error = match normalized_path.as_deref() {
            Some(path) => match select_comment_target(&finding.code_location.line_range, changed_lines.get(path)) {
                Some(target) => post_inline_comment(
                    pr_ref,
                    &pull_request.head_ref_oid,
                    path,
                    target.line,
                    target.side.as_github_value(),
                    &body,
                ).err(),
                None => Some(anyhow::anyhow!(
                    "No changed diff line matched this finding on either side of the PR."
                )),
            },
            None => Some(anyhow::anyhow!(
                "comment path is outside checked out repo: {}",
                finding.code_location.absolute_file_path.display()
            )),
        };

        if let Some(error) = inline_error {
            let top_level_body = render_top_level_comment_body(finding, &path_for_comment);
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
        finding.title.trim().to_string(),
        String::new(),
        finding.body.trim().to_string(),
    ];
    if let Some(priority) = finding.priority {
        lines.push(String::new());
        lines.push(format!("Priority: P{priority}"));
    }
    lines.push(format!("Confidence: {:.2}", finding.confidence_score));
    lines.join("\n")
}

fn render_top_level_comment_body(finding: &ReviewFinding, path: &str) -> String {
    let line_range = &finding.code_location.line_range;
    let location = if line_range.end > line_range.start {
        format!("{path}:{}-{}", line_range.start, line_range.end)
    } else {
        format!("{path}:{}", line_range.start)
    };

    let mut lines = vec![
        finding.title.trim().to_string(),
        String::new(),
        format!("File: `{location}`"),
        String::new(),
        finding.body.trim().to_string(),
    ];
    if let Some(priority) = finding.priority {
        lines.push(String::new());
        lines.push(format!("Priority: P{priority}"));
    }
    lines.push(format!("Confidence: {:.2}", finding.confidence_score));
    lines.join("\n")
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

fn review_pull_request_label(pull_request: &ReviewPullRequest) -> String {
    format!(
        "{}/{}#{} {}",
        pull_request.owner, pull_request.repo, pull_request.number, pull_request.title
    )
}

fn run_gh(args: Vec<String>, cwd: Option<&Path>) -> Result<String> {
    let mut command = Command::new("gh");
    command.args(args);
    if let Some(cwd) = cwd {
        command.current_dir(cwd);
    }

    let output = command.output().context("failed to launch gh")?;
    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let trimmed = stderr.trim();
        if trimmed.is_empty() {
            bail!(
                "gh command failed with status {}",
                output.status.code().unwrap_or(1)
            );
        }
        bail!("{trimmed}");
    }

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

#[derive(Debug, Clone)]
struct PullRequestReference {
    owner: String,
    repo: String,
    number: u64,
}

impl PullRequestReference {
    fn repo_name_with_owner(&self) -> String {
        format!("{}/{}", self.owner, self.repo)
    }
}

fn parse_pull_request_reference(raw: &str) -> Result<PullRequestReference> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        bail!("Missing pull request reference");
    }

    if let Some(value) = parse_pull_request_url(trimmed)? {
        return Ok(value);
    }

    if let Some((repo_name_with_owner, number_raw)) = trimmed.split_once('#') {
        let Some((owner, repo)) = repo_name_with_owner.split_once('/') else {
            bail!("Invalid pull request reference: {trimmed}");
        };
        let number = number_raw
            .parse::<u64>()
            .with_context(|| format!("invalid pull request number in {trimmed}"))?;
        return Ok(PullRequestReference {
            owner: owner.to_string(),
            repo: repo.to_string(),
            number,
        });
    }

    bail!("Invalid pull request reference: {trimmed}")
}

fn parse_pull_request_url(raw: &str) -> Result<Option<PullRequestReference>> {
    if !raw.starts_with("https://github.com/") {
        return Ok(None);
    }

    let suffix = raw.trim_start_matches("https://github.com/");
    let segments: Vec<&str> = suffix.split('/').collect();
    if segments.len() < 4 || segments[2] != "pull" {
        bail!("Invalid GitHub pull request URL: {raw}");
    }

    let number = segments[3]
        .parse::<u64>()
        .with_context(|| format!("invalid pull request number in {raw}"))?;
    Ok(Some(PullRequestReference {
        owner: segments[0].to_string(),
        repo: segments[1].to_string(),
        number,
    }))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;

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

    #[test]
    fn extracts_upstream_string_constant() {
        let source = r#"const BASE_BRANCH_PROMPT: &str = "hello {baseBranch}";"#;
        let value = extract_rust_string_constant(source, "BASE_BRANCH_PROMPT").unwrap();
        assert_eq!(value, "hello {baseBranch}");
    }

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
    fn loads_review_jobs_newest_first() {
        let root = unique_test_dir();
        let reviews_dir = root.join("reviews");
        fs::create_dir_all(reviews_dir.join("first")).unwrap();
        fs::create_dir_all(reviews_dir.join("second")).unwrap();

        fs::write(
            reviews_dir.join("first").join("job.json"),
            serde_json::to_vec(&ReviewJobSnapshot {
                id: "first".to_string(),
                pull_request: "owner/repo#1".to_string(),
                owner: "owner".to_string(),
                repo: "repo".to_string(),
                number: 1,
                url: None,
                status: ReviewJobStatus::Completed,
                current_step: "completed".to_string(),
                created_at: "2026-01-01T00:00:00Z".to_string(),
                started_at: None,
                finished_at: None,
                posted_comments: 1,
                failed_comments: 0,
                failed_comment_details: Vec::new(),
                summary: None,
                error: None,
            })
            .unwrap(),
        )
        .unwrap();
        fs::write(
            reviews_dir.join("second").join("job.json"),
            serde_json::to_vec(&ReviewJobSnapshot {
                id: "second".to_string(),
                pull_request: "owner/repo#2".to_string(),
                owner: "owner".to_string(),
                repo: "repo".to_string(),
                number: 2,
                url: None,
                status: ReviewJobStatus::Running,
                current_step: "running_codex_exec".to_string(),
                created_at: "2026-01-02T00:00:00Z".to_string(),
                started_at: None,
                finished_at: None,
                posted_comments: 0,
                failed_comments: 0,
                failed_comment_details: Vec::new(),
                summary: None,
                error: None,
            })
            .unwrap(),
        )
        .unwrap();

        let layout = StateLayout {
            root: root.clone(),
            tasks_dir: root.join("tasks"),
            config_file: root.join("config.json"),
        };

        let jobs = load_review_jobs(&layout).unwrap();
        assert_eq!(jobs.len(), 2);
        assert_eq!(jobs[0].id, "second");
        assert_eq!(jobs[1].id, "first");

        let _ = fs::remove_dir_all(root);
    }

    #[test]
    fn loads_one_review_job_by_id() {
        let root = unique_test_dir();
        let review_dir = root.join("reviews").join("job-123");
        fs::create_dir_all(&review_dir).unwrap();
        fs::write(
            review_dir.join("job.json"),
            serde_json::to_vec(&ReviewJobSnapshot {
                id: "job-123".to_string(),
                pull_request: "owner/repo#3".to_string(),
                owner: "owner".to_string(),
                repo: "repo".to_string(),
                number: 3,
                url: Some("https://github.com/owner/repo/pull/3".to_string()),
                status: ReviewJobStatus::Failed,
                current_step: "posting_comments".to_string(),
                created_at: "2026-01-03T00:00:00Z".to_string(),
                started_at: Some("2026-01-03T00:00:01Z".to_string()),
                finished_at: Some("2026-01-03T00:00:02Z".to_string()),
                posted_comments: 0,
                failed_comments: 1,
                failed_comment_details: vec![ReviewCommentFailure {
                    title: "Example".to_string(),
                    path: Some("src/lib.rs".to_string()),
                    start_line: 10,
                    end_line: 10,
                    reason: "No changed diff line matched this finding on either side of the PR."
                        .to_string(),
                }],
                summary: Some("patch is incorrect".to_string()),
                error: Some("comment post failed".to_string()),
            })
            .unwrap(),
        )
        .unwrap();

        let layout = StateLayout {
            root: root.clone(),
            tasks_dir: root.join("tasks"),
            config_file: root.join("config.json"),
        };

        let job = load_review_job(&layout, "job-123").unwrap();
        assert_eq!(job.id, "job-123");
        assert_eq!(job.status, ReviewJobStatus::Failed);
        assert_eq!(job.failed_comment_details.len(), 1);

        let _ = fs::remove_dir_all(root);
    }

    fn unique_test_dir() -> PathBuf {
        std::env::temp_dir().join(format!("codex-core-review-tests-{}", Uuid::new_v4()))
    }
}
