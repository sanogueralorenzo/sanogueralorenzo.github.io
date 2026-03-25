use anyhow::{Context, Result, bail};
use crate::core::temp::temp_file_path;
use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};
use std::collections::HashSet;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use uuid::Uuid;

const REVIEW_PROMPT: &str = "Review this pull request and return only strict JSON with this shape: {\"summary\":\"string\",\"comments\":[{\"path\":\"relative/path\",\"line\":123,\"body\":\"one short paragraph\"}]}. Rules: only include actionable findings, only comment on changed lines from the pull request, use repo-relative paths, use current head file line numbers on the right side of the diff, and return comments:[] when there are no findings. Do not wrap the JSON in markdown fences.";

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
}

#[derive(Debug, Deserialize)]
struct CodexReviewOutput {
    summary: String,
    comments: Vec<CodexReviewComment>,
}

#[derive(Debug, Deserialize)]
struct CodexReviewComment {
    path: String,
    line: u64,
    body: String,
}

struct ReviewWorkspace {
    root: PathBuf,
    repo_dir: PathBuf,
}

impl Drop for ReviewWorkspace {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.root);
    }
}

pub fn handle_review(action: ReviewCommand) -> Result<()> {
    match action {
        ReviewCommand::List(args) => list_pull_requests(args),
        ReviewCommand::Run(args) => run_review(args),
    }
}

fn list_pull_requests(args: ReviewListArgs) -> Result<()> {
    let pull_requests = load_open_pull_requests()?;

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

fn run_review(args: ReviewRunArgs) -> Result<()> {
    let pr_ref = parse_pull_request_reference(&args.pull_request)?;
    let pull_request = fetch_pull_request_view(&pr_ref)?;
    let workspace = checkout_pull_request(&pr_ref)?;
    let codex_output = run_codex_review(&workspace.repo_dir, &pull_request.base_ref_name)?;
    let review = parse_codex_review_output(&codex_output)?;
    let result = post_review_comments(&pr_ref, &workspace.repo_dir, &pull_request, review)?;

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

fn load_open_pull_requests() -> Result<Vec<ReviewPullRequest>> {
    let owners = load_review_owners()?;
    let mut seen = HashSet::new();
    let mut pull_requests = Vec::new();

    for owner in owners {
        for pull_request in search_open_pull_requests_for_owner(&owner)? {
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
            "number,url,baseRefName".to_string(),
        ],
        None,
    )?;
    serde_json::from_str(&output).context("failed to parse gh pr view response")
}

fn checkout_pull_request(pr_ref: &PullRequestReference) -> Result<ReviewWorkspace> {
    let root = env::temp_dir().join(format!(
        "codex-core-review-{}-{}-{}-{}",
        pr_ref.owner,
        pr_ref.repo,
        pr_ref.number,
        Uuid::new_v4()
    ));
    let repo_dir = root.join(&pr_ref.repo);
    fs::create_dir_all(&root).with_context(|| format!("failed to create {}", root.display()))?;

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
    run_gh(
        vec![
            "pr".to_string(),
            "checkout".to_string(),
            pr_ref.number.to_string(),
        ],
        Some(&repo_dir),
    )?;

    Ok(ReviewWorkspace { root, repo_dir })
}

fn run_codex_review(repo_dir: &Path, base_ref_name: &str) -> Result<String> {
    let output = Command::new("codex")
        .current_dir(repo_dir)
        .env("NO_COLOR", "1")
        .arg("review")
        .arg("--base")
        .arg(base_ref_name)
        .arg(REVIEW_PROMPT)
        .output()
        .context("failed to launch codex review")?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        let trimmed = stderr.trim();
        if trimmed.is_empty() {
            bail!(
                "codex review exited with status {}",
                output.status.code().unwrap_or(1)
            );
        }
        bail!(
            "codex review exited with status {}: {}",
            output.status.code().unwrap_or(1),
            trimmed
        );
    }

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

fn parse_codex_review_output(output: &str) -> Result<CodexReviewOutput> {
    let json = extract_json_object(output)?;
    serde_json::from_str(&json).context("failed to parse codex review JSON")
}

fn extract_json_object(output: &str) -> Result<String> {
    let trimmed = output.trim();
    if trimmed.starts_with('{') && trimmed.ends_with('}') {
        return Ok(trimmed.to_string());
    }

    let Some(start) = trimmed.find('{') else {
        bail!("codex review output did not contain JSON");
    };
    let Some(end) = trimmed.rfind('}') else {
        bail!("codex review output did not contain a complete JSON object");
    };

    Ok(trimmed[start..=end].to_string())
}

fn post_review_comments(
    pr_ref: &PullRequestReference,
    repo_dir: &Path,
    pull_request: &PullRequestView,
    review: CodexReviewOutput,
) -> Result<ReviewRunResult> {
    let mut posted_comments = 0usize;
    let mut failed_comments = 0usize;

    for comment in review.comments {
        let path = normalize_comment_path(&comment.path, repo_dir)?;
        if post_inline_comment(pr_ref, &path, comment.line, &comment.body).is_ok() {
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
        summary: review.summary,
    })
}

fn normalize_comment_path(raw_path: &str, repo_dir: &Path) -> Result<String> {
    let trimmed = raw_path.trim();
    if trimmed.is_empty() {
        bail!("codex review returned an empty comment path");
    }

    let path = PathBuf::from(trimmed);
    if path.is_absolute() {
        let relative = path
            .strip_prefix(repo_dir)
            .with_context(|| format!("comment path is outside checked out repo: {}", path.display()))?;
        return Ok(relative.to_string_lossy().into_owned());
    }

    Ok(trimmed.to_string())
}

fn post_inline_comment(
    pr_ref: &PullRequestReference,
    path: &str,
    line: u64,
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
        "side": "RIGHT"
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
            bail!("gh command failed with status {}", output.status.code().unwrap_or(1));
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
    fn extracts_json_object_from_fenced_output() {
        let output = "```json\n{\"summary\":\"ok\",\"comments\":[]}\n```";
        let json = extract_json_object(output).unwrap();
        assert_eq!(json, "{\"summary\":\"ok\",\"comments\":[]}");
    }
}
