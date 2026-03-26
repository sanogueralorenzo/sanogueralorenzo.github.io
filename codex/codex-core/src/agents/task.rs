use super::AvailableProject;
use super::StateLayout;
use super::load_agents_config;
use anyhow::{Context, Result, bail};
use clap::{Args, Subcommand};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::ffi::OsStr;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use uuid::Uuid;

const JIRA_BASE_URL: &str = "https://tonal.atlassian.net";
const TASK_BRANCH_PREFIX: &str = "msanoguera/";
const TASK_OUTPUT_FILE: &str = ".codex-task-result.json";
const SUPPORTED_PROJECTS: &[TaskProject] = &[
    TaskProject {
        key: "TS",
        repo_full_name: "tonalfitness/tonal",
        default_branch: "main",
    },
    TaskProject {
        key: "MOB",
        repo_full_name: "tonalfitness/mobile",
        default_branch: "main",
    },
    TaskProject {
        key: "API",
        repo_full_name: "tonalfitness/api-go",
        default_branch: "main",
    },
];

#[derive(Subcommand, Debug)]
pub(super) enum TaskCommand {
    /// List assigned Jira work items from the current sprint
    List(TaskListArgs),
    /// Run a Jira task end to end in a disposable worktree
    Run(TaskRunArgs),
    /// List persisted task jobs
    Jobs(TaskJobsArgs),
    /// Show one persisted task job
    Show(TaskShowArgs),
}

#[derive(Args, Debug)]
pub(super) struct TaskListArgs {
    #[arg(long)]
    pub json: bool,
}

#[derive(Args, Debug)]
pub(super) struct TaskRunArgs {
    pub ticket: String,
    #[arg(long)]
    pub json: bool,
}

#[derive(Args, Debug)]
pub(super) struct TaskJobsArgs {
    #[arg(long)]
    pub json: bool,
}

#[derive(Args, Debug)]
pub(super) struct TaskShowArgs {
    pub job_id: String,
    #[arg(long)]
    pub json: bool,
}

#[derive(Clone, Copy)]
struct TaskProject {
    key: &'static str,
    repo_full_name: &'static str,
    default_branch: &'static str,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TaskCandidate {
    pub ticket: String,
    pub summary: String,
    pub issue_url: String,
    pub repo_full_name: String,
    pub project_key: String,
    pub status: String,
    pub priority: String,
}

#[derive(Clone, Copy, Debug, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum TaskJobStatus {
    InProgress,
    Completed,
    Failed,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TaskJob {
    pub id: String,
    pub ticket: String,
    pub summary: String,
    pub issue_url: String,
    pub repo_full_name: String,
    pub branch: String,
    pub status: TaskJobStatus,
    pub current_step: String,
    pub created_at: String,
    pub updated_at: String,
    pub finished_at: Option<String>,
    pub pr_url: Option<String>,
    pub result_summary: Option<String>,
    pub error: Option<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct TaskRunResult {
    pub task_id: String,
    pub ticket: String,
    pub repo_full_name: String,
    pub branch: String,
    pub pr_url: Option<String>,
    pub summary: String,
    pub status: TaskJobStatus,
}

#[derive(Debug, Deserialize)]
struct JiraIssueSummary {
    key: String,
    fields: JiraIssueFields,
}

#[derive(Clone, Debug, Deserialize)]
struct JiraIssueFields {
    summary: String,
    status: JiraNamedField,
    priority: JiraNamedField,
    #[serde(default)]
    description: Option<Value>,
}

#[derive(Clone, Debug, Deserialize)]
struct JiraNamedField {
    name: String,
}

#[derive(Debug, Deserialize)]
struct JiraIssueView {
    key: String,
    fields: JiraIssueFields,
}

#[derive(Debug, Deserialize)]
struct CodexTaskExecResult {
    summary: String,
    pr_url: Option<String>,
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

pub(super) fn handle_task(action: TaskCommand, layout: &StateLayout) -> Result<()> {
    super::ensure_state_layout(layout)?;
    match action {
        TaskCommand::List(args) => task_list(layout, args),
        TaskCommand::Run(args) => task_run(layout, args),
        TaskCommand::Jobs(args) => task_jobs(layout, args),
        TaskCommand::Show(args) => task_show(layout, args),
    }
}

fn task_list(layout: &StateLayout, args: TaskListArgs) -> Result<()> {
    let candidates = load_task_candidates(layout)?;
    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&candidates)
                .context("failed to serialize task candidates")?
        );
        return Ok(());
    }

    if candidates.is_empty() {
        println!("No assigned Jira tasks found in the current sprint.");
        return Ok(());
    }

    for candidate in candidates {
        println!(
            "{} {:<12} {}",
            candidate.ticket, candidate.priority, candidate.summary
        );
    }
    Ok(())
}

fn task_run(layout: &StateLayout, args: TaskRunArgs) -> Result<()> {
    validate_ticket_key(&args.ticket)?;
    let issue = load_issue(&args.ticket)?;
    let project = project_for_ticket(&issue.key)?;
    let branch = branch_name(&issue.key, &issue.fields.summary);
    let now = super::now_utc();
    let task_id = Uuid::new_v4().to_string();

    let mut job = TaskJob {
        id: task_id.clone(),
        ticket: issue.key.clone(),
        summary: issue.fields.summary.clone(),
        issue_url: issue_url(&issue.key),
        repo_full_name: project.repo_full_name.to_string(),
        branch: branch.clone(),
        status: TaskJobStatus::InProgress,
        current_step: "preparing_repo".to_string(),
        created_at: now.clone(),
        updated_at: now,
        finished_at: None,
        pr_url: None,
        result_summary: None,
        error: None,
    };
    write_task_job(layout, &job)?;

    let result = run_task_job(layout, project, &issue, &branch, &mut job);
    match result {
        Ok(run_result) => {
            if args.json {
                println!(
                    "{}",
                    serde_json::to_string_pretty(&run_result)
                        .context("failed to serialize task run result")?
                );
            } else {
                println!("Task ID: {}", run_result.task_id);
                println!("Ticket: {}", run_result.ticket);
                println!("Repo: {}", run_result.repo_full_name);
                println!("Branch: {}", run_result.branch);
                if let Some(pr_url) = &run_result.pr_url {
                    println!("PR: {}", pr_url);
                }
                println!("Summary: {}", run_result.summary);
            }
            Ok(())
        }
        Err(error) => {
            job.status = TaskJobStatus::Failed;
            job.current_step = "failed".to_string();
            job.updated_at = super::now_utc();
            job.finished_at = Some(job.updated_at.clone());
            job.error = Some(error.to_string());
            write_task_job(layout, &job)?;
            Err(error)
        }
    }
}

fn task_jobs(layout: &StateLayout, args: TaskJobsArgs) -> Result<()> {
    let mut jobs = load_task_jobs(layout)?;
    jobs.sort_by(|left, right| right.created_at.cmp(&left.created_at));

    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&jobs).context("failed to serialize task jobs")?
        );
        return Ok(());
    }

    if jobs.is_empty() {
        println!("No task jobs available.");
        return Ok(());
    }

    println!(
        "{:<36} {:<12} {:<12} CURRENT_STEP",
        "ID", "TICKET", "STATUS"
    );
    for job in jobs {
        println!(
            "{:<36} {:<12} {:<12} {}",
            job.id,
            job.ticket,
            task_status_text(job.status),
            job.current_step
        );
    }
    Ok(())
}

fn task_show(layout: &StateLayout, args: TaskShowArgs) -> Result<()> {
    let job = read_task_job(layout, &args.job_id)?;
    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&job).context("failed to serialize task job")?
        );
        return Ok(());
    }

    println!("id: {}", job.id);
    println!("ticket: {}", job.ticket);
    println!("status: {}", task_status_text(job.status));
    println!("current_step: {}", job.current_step);
    println!("repo: {}", job.repo_full_name);
    println!("branch: {}", job.branch);
    println!("created_at: {}", job.created_at);
    println!("updated_at: {}", job.updated_at);
    if let Some(pr_url) = job.pr_url {
        println!("pr_url: {}", pr_url);
    }
    if let Some(summary) = job.result_summary {
        println!("summary: {}", summary);
    }
    if let Some(error) = job.error {
        println!("error: {}", error);
    }
    Ok(())
}

fn run_task_job(
    layout: &StateLayout,
    project: TaskProject,
    issue: &JiraIssueView,
    branch: &str,
    job: &mut TaskJob,
) -> Result<TaskRunResult> {
    let cache_repo_path = prepare_cache_repo(layout, project, job)?;
    let worktree_path =
        create_task_worktree(layout, &cache_repo_path, project.default_branch, branch)?;
    let _worktree_guard = WorktreeGuard {
        cache_repo_path,
        worktree_path: worktree_path.clone(),
    };

    job.current_step = "running_codex_exec".to_string();
    job.updated_at = super::now_utc();
    write_task_job(layout, job)?;

    let exec_result = run_codex_task(issue, branch, project.repo_full_name, &worktree_path)?;
    job.status = TaskJobStatus::Completed;
    job.current_step = "completed".to_string();
    job.updated_at = super::now_utc();
    job.finished_at = Some(job.updated_at.clone());
    job.pr_url = exec_result.pr_url.clone();
    job.result_summary = Some(exec_result.summary.clone());
    write_task_job(layout, job)?;

    Ok(TaskRunResult {
        task_id: job.id.clone(),
        ticket: job.ticket.clone(),
        repo_full_name: job.repo_full_name.clone(),
        branch: job.branch.clone(),
        pr_url: job.pr_url.clone(),
        summary: exec_result.summary,
        status: job.status,
    })
}

fn load_task_candidates(layout: &StateLayout) -> Result<Vec<TaskCandidate>> {
    let project_keys = selected_project_keys(layout)?;
    if project_keys.is_empty() {
        return Ok(Vec::new());
    }

    let jql = format!(
        "project in ({}) AND assignee = currentUser() AND Sprint in openSprints() AND statusCategory != Done ORDER BY Rank ASC",
        project_keys.join(",")
    );
    let issues: Vec<JiraIssueSummary> = run_json_command(
        "acli",
        &[
            "jira",
            "workitem",
            "search",
            "--jql",
            &jql,
            "--fields",
            "key,summary,status,priority",
            "--paginate",
            "--json",
        ],
        None,
    )?;

    Ok(issues
        .into_iter()
        .filter_map(|issue| {
            let project = project_for_ticket(&issue.key).ok()?;
            Some(TaskCandidate {
                ticket: issue.key.clone(),
                summary: issue.fields.summary,
                issue_url: issue_url(&issue.key),
                repo_full_name: project.repo_full_name.to_string(),
                project_key: project.key.to_string(),
                status: issue.fields.status.name,
                priority: issue.fields.priority.name,
            })
        })
        .collect())
}

fn selected_project_keys(layout: &StateLayout) -> Result<Vec<String>> {
    let config = load_agents_config(layout)?;
    let available_projects = list_available_projects()?;
    let mut keys = if config.allowed_projects.is_empty() {
        SUPPORTED_PROJECTS
            .iter()
            .map(|project| project.key.to_string())
            .collect::<Vec<_>>()
    } else {
        available_projects
            .into_iter()
            .filter(|project| config.allowed_projects.contains(&project.id))
            .map(|project| project.key)
            .collect::<Vec<_>>()
    };
    keys.retain(|key| SUPPORTED_PROJECTS.iter().any(|project| project.key == key));
    keys.sort();
    keys.dedup();
    Ok(keys)
}

fn list_available_projects() -> Result<Vec<AvailableProject>> {
    #[derive(Deserialize)]
    struct ListedProject {
        id: String,
        key: String,
    }

    let output = run_command(
        "acli",
        &["jira", "project", "list", "--json", "--paginate"],
        None,
        None,
    )?;
    let mut projects = serde_json::from_str::<Vec<ListedProject>>(&output)
        .context("failed to parse acli project list response")?
        .into_iter()
        .filter_map(|project| {
            project.id.parse::<u64>().ok().map(|id| AvailableProject {
                id,
                key: project.key,
            })
        })
        .collect::<Vec<_>>();
    projects.sort_by(|left, right| {
        left.key
            .cmp(&right.key)
            .then_with(|| left.id.cmp(&right.id))
    });
    projects.dedup_by(|left, right| left.id == right.id);
    Ok(projects)
}

fn load_issue(ticket: &str) -> Result<JiraIssueView> {
    run_json_command(
        "acli",
        &["jira", "workitem", "view", ticket, "--json"],
        None,
    )
}

fn prepare_cache_repo(
    layout: &StateLayout,
    project: TaskProject,
    job: &mut TaskJob,
) -> Result<PathBuf> {
    let (owner, repo) = split_repo_name(project.repo_full_name)?;
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
                project.repo_full_name,
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
    write_task_job(layout, job)?;

    run_command(
        "git",
        &["fetch", "--all", "--prune"],
        Some(&repo_path),
        None,
    )?;
    run_command(
        "git",
        &["checkout", project.default_branch],
        Some(&repo_path),
        None,
    )?;
    run_command(
        "git",
        &["pull", "--ff-only", "origin", project.default_branch],
        Some(&repo_path),
        None,
    )?;
    Ok(repo_path)
}

fn create_task_worktree(
    layout: &StateLayout,
    cache_repo_path: &Path,
    default_branch: &str,
    branch: &str,
) -> Result<PathBuf> {
    let worktree_path = layout.worktrees_dir().join("tasks").join(format!(
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

fn run_codex_task(
    issue: &JiraIssueView,
    branch: &str,
    repo_full_name: &str,
    worktree_path: &Path,
) -> Result<CodexTaskExecResult> {
    let prompt = build_task_prompt(issue, branch, repo_full_name);
    let output_path = worktree_path.join(TASK_OUTPUT_FILE);

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
            .context("failed to write task prompt to codex exec")?;
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
    parse_codex_task_result(&final_message)
}

fn build_task_prompt(issue: &JiraIssueView, branch: &str, repo_full_name: &str) -> String {
    let description = issue
        .fields
        .description
        .as_ref()
        .map(description_text)
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "No additional Jira description was provided.".to_string());

    format!(
        "You are implementing Jira ticket {ticket} in repository {repo}.\n\nTicket summary:\n{summary}\n\nTicket description:\n{description}\n\nRequirements:\n- Work on the already checked out branch `{branch}`. Do not create or switch to another branch.\n- The repository cache has already been updated and this worktree already starts from the latest `{default_branch}`.\n- Implement the ticket end to end in this repository.\n- Run the narrowest relevant validation for the code you change.\n- Commit the changes, push the branch, and open a GitHub pull request.\n- Use `acli jira` for Jira references and `gh` for GitHub actions.\n- Follow the repository AGENTS.md instructions exactly.\n- Final response must be JSON only with this shape: {{\"summary\":\"<short implementation summary>\",\"pr_url\":\"<https://github.com/.../pull/...>\"}}\n\nJira issue URL: {issue_url}\n",
        ticket = issue.key,
        repo = repo_full_name,
        summary = issue.fields.summary,
        description = description,
        branch = branch,
        default_branch = project_for_ticket(&issue.key)
            .map(|project| project.default_branch)
            .unwrap_or("main"),
        issue_url = issue_url(&issue.key),
    )
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

fn parse_codex_task_result(text: &str) -> Result<CodexTaskExecResult> {
    if let Ok(result) = serde_json::from_str::<CodexTaskExecResult>(text.trim()) {
        return Ok(result);
    }

    let start = text
        .find('{')
        .context("codex task output did not contain JSON")?;
    let end = text
        .rfind('}')
        .context("codex task output did not contain JSON")?;
    serde_json::from_str::<CodexTaskExecResult>(&text[start..=end])
        .context("failed to parse codex task result JSON")
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

fn write_task_job(layout: &StateLayout, job: &TaskJob) -> Result<()> {
    let path = task_job_path(layout, &job.id);
    let payload = serde_json::to_string_pretty(job).context("failed to serialize task job")?;
    fs::write(&path, payload).with_context(|| format!("failed to write {}", path.display()))
}

fn read_task_job(layout: &StateLayout, job_id: &str) -> Result<TaskJob> {
    let path = task_job_path(layout, job_id);
    let payload =
        fs::read_to_string(&path).with_context(|| format!("failed to read {}", path.display()))?;
    serde_json::from_str(&payload).with_context(|| format!("failed to parse {}", path.display()))
}

fn load_task_jobs(layout: &StateLayout) -> Result<Vec<TaskJob>> {
    if !layout.tasks_dir.exists() {
        return Ok(Vec::new());
    }

    let mut jobs = Vec::new();
    for entry in fs::read_dir(&layout.tasks_dir)
        .with_context(|| format!("failed to read {}", layout.tasks_dir.display()))?
    {
        let entry = entry?;
        let path = entry.path();
        if path.extension() != Some(OsStr::new("json")) {
            continue;
        }
        let payload = fs::read_to_string(&path)
            .with_context(|| format!("failed to read {}", path.display()))?;
        let job: TaskJob = serde_json::from_str(&payload)
            .with_context(|| format!("failed to parse {}", path.display()))?;
        jobs.push(job);
    }
    Ok(jobs)
}

fn task_job_path(layout: &StateLayout, job_id: &str) -> PathBuf {
    layout.tasks_dir.join(format!("{job_id}.json"))
}

fn task_status_text(status: TaskJobStatus) -> &'static str {
    match status {
        TaskJobStatus::InProgress => "in_progress",
        TaskJobStatus::Completed => "completed",
        TaskJobStatus::Failed => "failed",
    }
}

fn validate_ticket_key(ticket: &str) -> Result<()> {
    if ticket.is_empty() {
        bail!("Invalid ticket key: empty");
    }
    if ticket
        .chars()
        .all(|ch| ch.is_ascii_alphanumeric() || ch == '.' || ch == '_' || ch == '-')
    {
        return Ok(());
    }
    bail!(
        "Invalid ticket key: {ticket}\nAllowed characters: letters, numbers, dot, underscore, hyphen."
    )
}

fn project_for_ticket(ticket: &str) -> Result<TaskProject> {
    let project_key = ticket
        .split('-')
        .next()
        .context("ticket key missing project prefix")?;
    SUPPORTED_PROJECTS
        .iter()
        .copied()
        .find(|project| project.key == project_key)
        .with_context(|| format!("Unsupported Jira project for task automation: {project_key}"))
}

fn branch_name(ticket: &str, summary: &str) -> String {
    let summary_slug = summary
        .split(|ch: char| !ch.is_ascii_alphanumeric())
        .filter(|part| !part.is_empty())
        .take(2)
        .map(|part| part.to_ascii_lowercase())
        .collect::<Vec<_>>()
        .join("_");
    let fallback = if summary_slug.is_empty() {
        "task"
    } else {
        &summary_slug
    };
    format!(
        "{}{ticket}_{fallback}",
        TASK_BRANCH_PREFIX,
        ticket = ticket.to_ascii_lowercase()
    )
}

fn issue_url(ticket: &str) -> String {
    format!("{JIRA_BASE_URL}/browse/{ticket}")
}

fn split_repo_name(repo_full_name: &str) -> Result<(&str, &str)> {
    repo_full_name
        .split_once('/')
        .context("invalid repo full name")
}

pub(super) fn pick_next_pending_task(
    layout: &StateLayout,
) -> Result<Option<(String, String, String)>> {
    let mut jobs: Vec<TaskJob> = load_task_jobs(layout)?
        .into_iter()
        .filter(|job| job.status == TaskJobStatus::InProgress)
        .collect();
    jobs.sort_by(|left, right| left.created_at.cmp(&right.created_at));

    Ok(jobs
        .into_iter()
        .next()
        .map(|job| (job.ticket, job.created_at, job.updated_at)))
}

#[cfg(test)]
mod tests {
    use super::branch_name;

    #[test]
    fn branch_name_uses_ticket_and_two_summary_words() {
        assert_eq!(
            branch_name(
                "TS-123",
                "OpenGL Testing & Model Initialization Improvements"
            ),
            "msanoguera/ts-123_opengl_testing"
        );
    }
}
