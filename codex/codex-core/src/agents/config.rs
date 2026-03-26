use super::AvailableProject;
use super::AvailableRepo;
use super::RepoOwner;
use super::ReviewPublishMode;
use super::StateLayout;
use anyhow::{Context, Result, bail};
use clap::{Args, Subcommand};
use serde::Deserialize;
use std::path::Path;
use std::process::Command;

#[derive(Subcommand, Debug)]
pub(super) enum ConfigCommand {
    /// Initialize local agent configuration
    Init,
    /// Show current agent configuration
    Show(ConfigShowArgs),
    /// List GitHub repos available for review filtering
    AvailableRepos(ConfigAvailableReposArgs),
    /// List Jira projects available for task filtering
    AvailableProjects(ConfigAvailableProjectsArgs),
    /// Set the allowed review repo filters
    SetAllowedRepos(ConfigSetAllowedReposArgs),
    /// Set the allowed Jira project filters
    SetAllowedProjects(ConfigSetAllowedProjectsArgs),
    /// Set the default review publish mode
    SetReviewMode(ConfigSetReviewModeArgs),
    /// Clear allowed review repo filters
    ClearAllowedRepos,
    /// Clear allowed Jira project filters
    ClearAllowedProjects,
}

#[derive(Args, Debug)]
pub(super) struct ConfigShowArgs {
    #[arg(long)]
    pub json: bool,
}

#[derive(Args, Debug)]
pub(super) struct ConfigAvailableReposArgs {
    #[arg(long)]
    pub json: bool,
}

#[derive(Args, Debug)]
pub(super) struct ConfigAvailableProjectsArgs {
    #[arg(long)]
    pub json: bool,
}

#[derive(Args, Debug)]
pub(super) struct ConfigSetAllowedReposArgs {
    pub repos: Vec<String>,
}

#[derive(Args, Debug)]
pub(super) struct ConfigSetAllowedProjectsArgs {
    pub project_ids: Vec<u64>,
}

#[derive(Args, Debug)]
pub(super) struct ConfigSetReviewModeArgs {
    pub mode: ReviewPublishMode,
}

#[derive(Debug, Deserialize)]
struct ListedRepo {
    name: String,
    owner: RepoOwner,
    #[serde(rename = "isArchived")]
    is_archived: bool,
    #[serde(rename = "viewerPermission")]
    viewer_permission: String,
}

#[derive(Debug, Deserialize)]
struct ListedProject {
    id: String,
    key: String,
}

pub(super) fn handle_config(action: ConfigCommand, layout: &StateLayout) -> Result<()> {
    super::ensure_state_layout(layout)?;
    match action {
        ConfigCommand::Init => init(layout),
        ConfigCommand::Show(args) => config_show(layout, args),
        ConfigCommand::AvailableRepos(args) => config_available_repos(args),
        ConfigCommand::AvailableProjects(args) => config_available_projects(args),
        ConfigCommand::SetAllowedRepos(args) => config_set_allowed_repos(layout, args),
        ConfigCommand::SetAllowedProjects(args) => config_set_allowed_projects(layout, args),
        ConfigCommand::SetReviewMode(args) => config_set_review_mode(layout, args),
        ConfigCommand::ClearAllowedRepos => config_clear_allowed_repos(layout),
        ConfigCommand::ClearAllowedProjects => config_clear_allowed_projects(layout),
    }
}

fn init(layout: &StateLayout) -> Result<()> {
    let already_initialized = layout.config_file.exists();
    if already_initialized {
        println!(
            "codex-core agents state already initialized at: {}",
            layout.root.display()
        );
    } else {
        println!(
            "Initialized codex-core agents state at: {}",
            layout.root.display()
        );
    }
    Ok(())
}

fn config_show(layout: &StateLayout, args: ConfigShowArgs) -> Result<()> {
    let config = super::load_agents_config(layout)?;
    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&config).context("failed to serialize agents config")?
        );
        return Ok(());
    }

    println!("review_mode={}", config.review_mode.as_str());
    if config.allowed_repos.is_empty() {
        println!("allowed_repos=");
    } else {
        println!("allowed_repos={}", config.allowed_repos.join(","));
    }
    if config.allowed_projects.is_empty() {
        println!("allowed_projects=");
    } else {
        let project_ids = config
            .allowed_projects
            .iter()
            .map(u64::to_string)
            .collect::<Vec<_>>();
        println!("allowed_projects={}", project_ids.join(","));
    }
    Ok(())
}

fn config_available_repos(args: ConfigAvailableReposArgs) -> Result<()> {
    let repos = list_available_repos()?;
    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&repos).context("failed to serialize available repos")?
        );
        return Ok(());
    }

    for repo in repos {
        println!("{}", repo.full_name);
    }
    Ok(())
}

fn config_available_projects(args: ConfigAvailableProjectsArgs) -> Result<()> {
    let projects = list_available_projects()?;
    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&projects)
                .context("failed to serialize available projects")?
        );
        return Ok(());
    }

    for project in projects {
        println!("{} {}", project.id, project.key);
    }
    Ok(())
}

fn config_set_allowed_repos(layout: &StateLayout, args: ConfigSetAllowedReposArgs) -> Result<()> {
    let mut normalized = normalize_repo_filters(args.repos)?;
    normalized.sort();
    normalized.dedup();

    update_agents_config(layout, |config| {
        config.allowed_repos = normalized.clone();
    })?;

    if normalized.is_empty() {
        println!("Set allowed_repos=");
    } else {
        println!("Set allowed_repos={}", normalized.join(","));
    }
    Ok(())
}

fn config_set_allowed_projects(
    layout: &StateLayout,
    args: ConfigSetAllowedProjectsArgs,
) -> Result<()> {
    let mut project_ids = args.project_ids;
    project_ids.sort();
    project_ids.dedup();

    update_agents_config(layout, |config| {
        config.allowed_projects = project_ids.clone();
    })?;

    if project_ids.is_empty() {
        println!("Set allowed_projects=");
    } else {
        let values = project_ids.iter().map(u64::to_string).collect::<Vec<_>>();
        println!("Set allowed_projects={}", values.join(","));
    }
    Ok(())
}

fn config_set_review_mode(layout: &StateLayout, args: ConfigSetReviewModeArgs) -> Result<()> {
    update_agents_config(layout, |config| {
        config.review_mode = args.mode;
    })?;
    println!("Set review_mode={}", args.mode.as_str());
    Ok(())
}

fn config_clear_allowed_repos(layout: &StateLayout) -> Result<()> {
    update_agents_config(layout, |config| {
        config.allowed_repos.clear();
    })?;
    println!("Cleared allowed_repos");
    Ok(())
}

fn config_clear_allowed_projects(layout: &StateLayout) -> Result<()> {
    update_agents_config(layout, |config| {
        config.allowed_projects.clear();
    })?;
    println!("Cleared allowed_projects");
    Ok(())
}

fn list_available_repos() -> Result<Vec<AvailableRepo>> {
    let owners = load_repo_owners()?;
    let mut repos = Vec::new();
    for owner in owners {
        repos.extend(load_owner_repos(&owner)?);
    }

    repos.sort_by(|a, b| a.full_name.cmp(&b.full_name));
    repos.dedup_by(|a, b| a.full_name == b.full_name);
    Ok(repos)
}

fn list_available_projects() -> Result<Vec<AvailableProject>> {
    let output = run_acli_json(&["jira", "project", "list", "--json", "--paginate"])?;
    let mut projects: Vec<AvailableProject> = serde_json::from_str::<Vec<ListedProject>>(&output)
        .context("failed to parse acli project list response")?
        .into_iter()
        .filter_map(|project| {
            project.id.parse::<u64>().ok().map(|id| AvailableProject {
                id,
                key: project.key,
            })
        })
        .collect();

    projects.sort_by(|left, right| {
        left.key
            .cmp(&right.key)
            .then_with(|| left.id.cmp(&right.id))
    });
    projects.dedup_by(|left, right| left.id == right.id);
    Ok(projects)
}

fn normalize_repo_filters(repos: Vec<String>) -> Result<Vec<String>> {
    repos
        .into_iter()
        .map(|repo| {
            let trimmed = repo.trim();
            let Some((owner, name)) = trimmed.split_once('/') else {
                bail!("Invalid repo filter: {trimmed}. Expected OWNER/REPO.");
            };
            if owner.is_empty() || name.is_empty() || name.contains('/') {
                bail!("Invalid repo filter: {trimmed}. Expected OWNER/REPO.");
            }
            Ok(format!("{owner}/{name}"))
        })
        .collect()
}

fn load_repo_owners() -> Result<Vec<String>> {
    let viewer_output = run_gh_json(
        vec![
            "api".to_string(),
            "graphql".to_string(),
            "-f".to_string(),
            "query=query { viewer { login organizations(first: 100) { nodes { login } } } }"
                .to_string(),
        ],
        None,
    )?;
    let viewer: serde_json::Value =
        serde_json::from_str(&viewer_output).context("failed to parse gh viewer response")?;

    let mut owners = Vec::new();
    if let Some(login) = viewer["data"]["viewer"]["login"].as_str() {
        owners.push(login.to_string());
    }
    if let Some(nodes) = viewer["data"]["viewer"]["organizations"]["nodes"].as_array() {
        owners.extend(
            nodes
                .iter()
                .filter_map(|node| node["login"].as_str().map(ToString::to_string)),
        );
    }

    owners.sort();
    owners.dedup();
    Ok(owners)
}

fn load_owner_repos(owner: &str) -> Result<Vec<AvailableRepo>> {
    let output = run_gh_json(
        vec![
            "repo".to_string(),
            "list".to_string(),
            owner.to_string(),
            "--limit".to_string(),
            "1000".to_string(),
            "--json".to_string(),
            "name,owner,isArchived,viewerPermission".to_string(),
        ],
        None,
    )?;
    let listed: Vec<ListedRepo> =
        serde_json::from_str(&output).context("failed to parse gh repo list response")?;

    Ok(listed
        .into_iter()
        .filter(|repo| !repo.is_archived)
        .filter(|repo| {
            matches!(
                repo.viewer_permission.as_str(),
                "WRITE" | "MAINTAIN" | "ADMIN"
            )
        })
        .map(|repo| AvailableRepo {
            full_name: format!("{}/{}", repo.owner.login, repo.name),
        })
        .collect())
}

fn update_agents_config(
    layout: &StateLayout,
    update: impl FnOnce(&mut super::AgentsConfig),
) -> Result<()> {
    let mut config = super::load_agents_config(layout)?;
    update(&mut config);
    super::save_agents_config(layout, &config)
}

fn run_gh_json(args: Vec<String>, cwd: Option<&Path>) -> Result<String> {
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

fn run_acli_json(args: &[&str]) -> Result<String> {
    let mut command = Command::new("acli");
    command.args(args);

    let output = command
        .output()
        .with_context(|| format!("failed to run `acli {}`", args.join(" ")))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        if stderr.is_empty() {
            bail!(
                "acli {} failed with status {}",
                args.join(" "),
                output.status
            );
        }
        bail!("acli {}: {}", args.join(" "), stderr);
    }

    Ok(String::from_utf8_lossy(&output.stdout).to_string())
}

#[cfg(test)]
mod tests {
    use super::normalize_repo_filters;

    #[test]
    fn normalize_repo_filters_accepts_owner_repo() {
        let filters = normalize_repo_filters(vec!["openai/codex".to_string()]).unwrap();
        assert_eq!(filters, vec!["openai/codex"]);
    }

    #[test]
    fn normalize_repo_filters_rejects_invalid_shape() {
        let error = normalize_repo_filters(vec!["openai".to_string()]).unwrap_err();
        assert!(
            error
                .to_string()
                .contains("Invalid repo filter: openai. Expected OWNER/REPO.")
        );
    }
}
