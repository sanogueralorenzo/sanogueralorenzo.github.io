use super::PullRequestReference;
use super::ReviewPullRequest;
use crate::agents::AgentsConfig;
use anyhow::{Context, Result, bail};
use serde::Deserialize;
use std::collections::HashSet;
use std::path::Path;
use std::process::Command;

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
pub(super) struct PullRequestView {
    pub number: u64,
    pub url: String,
    #[serde(rename = "baseRefName")]
    pub base_ref_name: String,
    #[serde(rename = "headRefOid")]
    pub head_ref_oid: String,
}

pub(super) fn list_pull_requests_with_config(
    config: &AgentsConfig,
) -> Result<Vec<ReviewPullRequest>> {
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

pub(super) fn fetch_pull_request_view(pr_ref: &PullRequestReference) -> Result<PullRequestView> {
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

pub(super) fn review_pull_request_label(pull_request: &ReviewPullRequest) -> String {
    format!(
        "{}/{}#{} {}",
        pull_request.owner, pull_request.repo, pull_request.number, pull_request.title
    )
}

pub(super) fn run_gh(args: Vec<String>, cwd: Option<&Path>) -> Result<String> {
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
