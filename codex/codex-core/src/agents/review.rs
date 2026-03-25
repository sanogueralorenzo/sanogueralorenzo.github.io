use super::AgentsConfig;
use super::StateLayout;
use super::load_agents_config;
use crate::core::temp::temp_file_path;
use anyhow::{Context, Result, bail};
use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::collections::HashSet;
use std::env;
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
        updatedAt
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
    /// Review one pull request and post inline findings
    Run(ReviewRunArgs),
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

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewPullRequest {
    pub owner: String,
    pub repo: String,
    pub number: u64,
    pub title: String,
    pub url: String,
    pub updated_at: String,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct ReviewRunResult {
    pub owner: String,
    pub repo: String,
    pub number: u64,
    pub url: String,
    pub posted_comments: usize,
    pub failed_comments: usize,
    pub summary: String,
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
    #[serde(rename = "updatedAt")]
    updated_at: String,
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
    #[serde(rename = "headRefName")]
    head_ref_name: String,
}

struct ReviewWorkspace {
    root: PathBuf,
    repo_dir: PathBuf,
    delete_on_drop: bool,
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
        if self.delete_on_drop {
            let _ = fs::remove_dir_all(&self.root);
        }
    }
}

pub fn handle_review(action: ReviewCommand, layout: &StateLayout) -> Result<()> {
    match action {
        ReviewCommand::List(args) => list_pull_requests(layout, args),
        ReviewCommand::Run(args) => run_review(layout, args),
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
    let config = load_agents_config(layout)?;
    let pr_ref = parse_pull_request_reference(&args.pull_request)?;
    let pull_request = fetch_pull_request_view(&pr_ref)?;
    let workspace = checkout_pull_request(&config, &pr_ref, &pull_request)?;
    let upstream_prompts = load_upstream_review_prompts()?;
    let merge_base = resolve_merge_base(&workspace.repo_dir, &pull_request.base_ref_name)?;
    let review_request = build_base_branch_review_request(
        &upstream_prompts,
        &pull_request.base_ref_name,
        merge_base.as_deref(),
    );
    let prompt = format!("{}\n\n{}", upstream_prompts.review_rubric, review_request);
    let review = run_codex_exec_review(&workspace.repo_dir, &prompt)?;
    let changed_lines =
        collect_changed_diff_lines(&workspace.repo_dir, &pull_request.base_ref_name)?;
    let result = post_review_comments(
        &pr_ref,
        &workspace.repo_dir,
        &pull_request,
        review,
        &changed_lines,
    )?;

    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&result).context("failed to serialize review result")?
        );
        return Ok(());
    }

    if args.plain {
        println!(
            "{} {} {}",
            result.url, result.posted_comments, result.failed_comments
        );
        return Ok(());
    }

    println!("Reviewed {}", result.url);
    println!("Posted comments: {}", result.posted_comments);
    println!("Failed comments: {}", result.failed_comments);
    println!("Summary: {}", result.summary);
    Ok(())
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

    pull_requests.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
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
                updated_at: node.updated_at,
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
            "number,url,baseRefName,headRefName".to_string(),
        ],
        None,
    )?;
    serde_json::from_str(&output).context("failed to parse gh pr view response")
}

fn checkout_pull_request(
    config: &AgentsConfig,
    pr_ref: &PullRequestReference,
    pull_request: &PullRequestView,
) -> Result<ReviewWorkspace> {
    if let Some(project_home) = config.project_home.as_ref() {
        let root = project_home.join(&pr_ref.owner);
        let repo_dir = root.join(&pr_ref.repo);
        fs::create_dir_all(&root)
            .with_context(|| format!("failed to create {}", root.display()))?;

        if repo_dir.exists() {
            refresh_existing_checkout(&repo_dir, pr_ref, pull_request)?;
        } else {
            clone_and_checkout_pull_request(&repo_dir, pr_ref, pull_request)?;
        }

        return Ok(ReviewWorkspace {
            root,
            repo_dir,
            delete_on_drop: false,
        });
    }

    let root = env::temp_dir().join(format!(
        "codex-core-review-{}-{}-{}-{}",
        pr_ref.owner,
        pr_ref.repo,
        pr_ref.number,
        Uuid::new_v4()
    ));
    let repo_dir = root.join(&pr_ref.repo);
    fs::create_dir_all(&root).with_context(|| format!("failed to create {}", root.display()))?;
    clone_and_checkout_pull_request(&repo_dir, pr_ref, pull_request)?;

    Ok(ReviewWorkspace {
        root,
        repo_dir,
        delete_on_drop: true,
    })
}

fn clone_and_checkout_pull_request(
    repo_dir: &Path,
    pr_ref: &PullRequestReference,
    pull_request: &PullRequestView,
) -> Result<()> {
    run_gh(
        vec![
            "repo".to_string(),
            "clone".to_string(),
            pr_ref.repo_name_with_owner(),
            repo_dir.to_string_lossy().into_owned(),
            "--".to_string(),
            "--quiet".to_string(),
        ],
        None,
    )?;
    checkout_and_update_pull_request_branch(repo_dir, pr_ref, pull_request)
}

fn refresh_existing_checkout(
    repo_dir: &Path,
    pr_ref: &PullRequestReference,
    pull_request: &PullRequestView,
) -> Result<()> {
    if !repo_dir.join(".git").exists() {
        bail!(
            "Existing project path is not a git repository: {}",
            repo_dir.display()
        );
    }

    run_git(repo_dir, &["fetch", "--all", "--prune"])?;
    run_git(repo_dir, &["checkout", &pull_request.base_ref_name])?;
    run_git(
        repo_dir,
        &["pull", "--ff-only", "origin", &pull_request.base_ref_name],
    )?;
    checkout_and_update_pull_request_branch(repo_dir, pr_ref, pull_request)
}

fn checkout_and_update_pull_request_branch(
    repo_dir: &Path,
    pr_ref: &PullRequestReference,
    pull_request: &PullRequestView,
) -> Result<()> {
    run_gh(
        vec![
            "pr".to_string(),
            "checkout".to_string(),
            pr_ref.number.to_string(),
            "--repo".to_string(),
            pr_ref.repo_name_with_owner(),
        ],
        Some(repo_dir),
    )?;
    run_git(repo_dir, &["checkout", &pull_request.head_ref_name])?;
    run_git(repo_dir, &["pull", "--ff-only"])?;
    Ok(())
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
    let summary = summarize_review(&review);

    for finding in &review.findings {
        let path = match normalize_comment_path(&finding.code_location.absolute_file_path, repo_dir)
        {
            Ok(path) => path,
            Err(_) => {
                failed_comments += 1;
                continue;
            }
        };
        let Some(target) =
            select_comment_target(&finding.code_location.line_range, changed_lines.get(&path))
        else {
            failed_comments += 1;
            continue;
        };
        let body = render_inline_comment_body(&finding);
        if post_inline_comment(
            pr_ref,
            &path,
            target.line,
            target.side.as_github_value(),
            &body,
        )
        .is_ok()
        {
            posted_comments += 1;
        } else {
            failed_comments += 1;
        }
    }

    Ok(ReviewRunResult {
        owner: pr_ref.owner.clone(),
        repo: pr_ref.repo.clone(),
        number: pull_request.number,
        url: pull_request.url.clone(),
        posted_comments,
        failed_comments,
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

fn post_inline_comment(
    pr_ref: &PullRequestReference,
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
}
