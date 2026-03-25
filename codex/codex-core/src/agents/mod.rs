mod review;

use anyhow::{Context, Result, bail};
use chrono::Utc;
use clap::{Args, Parser, Subcommand};
use serde::{Deserialize, Serialize};
use std::env;
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::thread;
use std::time::Duration;

const DEFAULT_WORKER_INTERVAL_SECONDS: u64 = 30;

#[derive(Parser, Debug)]
#[command(name = "codex-core agents")]
#[command(about = "Track local tasks and run a basic worker loop")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Initialize local agent configuration
    Config {
        #[command(subcommand)]
        action: ConfigCommand,
    },
    /// Create/list/show tasks
    Task {
        #[command(subcommand)]
        action: TaskCommand,
    },
    /// Start autonomous worker loop
    Worker {
        #[command(subcommand)]
        action: WorkerCommand,
    },
    /// Review GitHub pull requests with Codex and post inline findings
    Review {
        #[command(subcommand)]
        action: review::ReviewCommand,
    },
}

#[derive(Subcommand, Debug)]
enum ConfigCommand {
    /// Initialize local agent configuration
    Init,
    /// Show current agent configuration
    Show(ConfigShowArgs),
    /// List GitHub repos available for review filtering
    AvailableRepos(ConfigAvailableReposArgs),
    /// Set the allowed review repo filters
    SetAllowedRepos(ConfigSetAllowedReposArgs),
    /// Clear allowed review repo filters
    ClearAllowedRepos,
}

#[derive(Subcommand, Debug)]
enum TaskCommand {
    /// Create task from ticket key
    Create(TaskCreateArgs),
    /// List tracked tasks
    List,
    /// Show task details by ticket key
    Show(TaskShowArgs),
}

#[derive(Subcommand, Debug)]
enum WorkerCommand {
    /// Start autonomous worker loop
    Start(WorkerStartArgs),
    /// Run a repeated loop using `codex exec`
    Loop(WorkerLoopArgs),
}

#[derive(Args, Debug)]
struct TaskCreateArgs {
    ticket: String,
}

#[derive(Args, Debug)]
struct TaskShowArgs {
    ticket: String,
}

#[derive(Args, Debug)]
struct WorkerStartArgs {
    /// Run exactly one worker cycle and exit
    #[arg(long)]
    once: bool,

    /// Polling interval for worker loop in seconds
    #[arg(long = "interval-seconds", default_value_t = DEFAULT_WORKER_INTERVAL_SECONDS)]
    interval_seconds: u64,
}

#[derive(Args, Debug)]
struct WorkerLoopArgs {
    /// Prompt to run on each iteration (or use --prompt-file)
    prompt: Option<String>,

    /// Read prompt from file instead of positional prompt
    #[arg(long = "prompt-file", value_name = "FILE", conflicts_with = "prompt")]
    prompt_file: Option<PathBuf>,

    /// Working directory for codex exec
    #[arg(long = "cd", value_name = "DIR", default_value = ".")]
    cd: PathBuf,

    /// Polling interval for worker loop in seconds
    #[arg(long = "interval-seconds", default_value_t = DEFAULT_WORKER_INTERVAL_SECONDS)]
    interval_seconds: u64,

    /// Maximum number of iterations before stopping
    #[arg(long = "max-iterations")]
    max_iterations: Option<u64>,

    /// Stop loop when final message contains this text
    #[arg(long = "stop-phrase", default_value = "LOOP_DONE")]
    stop_phrase: String,

    /// Optional model override passed to codex
    #[arg(long)]
    model: Option<String>,

    /// Run exactly one worker cycle and exit
    #[arg(long)]
    once: bool,

    /// Pass --full-auto to codex exec
    #[arg(long)]
    full_auto: bool,

    /// Pass --dangerously-bypass-approvals-and-sandbox to codex exec
    #[arg(long = "dangerously-bypass-approvals-and-sandbox")]
    dangerously_bypass_approvals_and_sandbox: bool,

    /// Pass --skip-git-repo-check to codex exec
    #[arg(long)]
    skip_git_repo_check: bool,
}

#[derive(Clone, Debug)]
struct StateLayout {
    root: PathBuf,
    tasks_dir: PathBuf,
    config_file: PathBuf,
}

#[derive(Args, Debug)]
struct ConfigShowArgs {
    #[arg(long)]
    json: bool,
}

#[derive(Args, Debug)]
struct ConfigAvailableReposArgs {
    #[arg(long)]
    json: bool,
}

#[derive(Args, Debug)]
struct ConfigSetAllowedReposArgs {
    repos: Vec<String>,
}

#[derive(Clone, Debug, Default, Serialize, Deserialize, PartialEq, Eq)]
struct AgentsConfig {
    state_version: u32,
    initialized_at: String,
    allowed_repos: Vec<String>,
}

#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
struct AvailableRepo {
    full_name: String,
}

#[derive(Debug, Deserialize)]
struct RepoOwner {
    login: String,
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

#[derive(Clone, Debug)]
struct TaskRecord {
    ticket: String,
    status: String,
    created_at: String,
    updated_at: String,
    path: PathBuf,
}

#[derive(Debug)]
struct LoopIterationResult {
    final_message: String,
}

struct CaffeinateGuard {
    child: Child,
}

impl Drop for CaffeinateGuard {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

pub fn run_from(args: Vec<OsString>) -> u8 {
    let mut normalized = Vec::with_capacity(args.len() + 1);
    normalized.push(OsString::from("codex-core agents"));
    if args.first().and_then(|value| value.to_str()) == Some("agents") {
        normalized.extend(args.into_iter().skip(1));
    } else {
        normalized.extend(args);
    }

    let cli = match Cli::try_parse_from(normalized) {
        Ok(cli) => cli,
        Err(error) => {
            let code = error.exit_code();
            let _ = error.print();
            return code as u8;
        }
    };

    match run(cli) {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("Error: {error}");
            1
        }
    }
}

fn run(cli: Cli) -> Result<()> {
    let layout = resolve_state_layout()?;

    match cli.command {
        Commands::Config { action } => handle_config(action, &layout),
        Commands::Task { action } => handle_task(action, &layout),
        Commands::Worker { action } => handle_worker(action, &layout),
        Commands::Review { action } => review::handle_review(action, &layout),
    }
}

fn handle_config(action: ConfigCommand, layout: &StateLayout) -> Result<()> {
    ensure_state_layout(layout)?;
    match action {
        ConfigCommand::Init => {
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
        ConfigCommand::Show(args) => config_show(layout, args),
        ConfigCommand::AvailableRepos(args) => config_available_repos(args),
        ConfigCommand::SetAllowedRepos(args) => config_set_allowed_repos(layout, args),
        ConfigCommand::ClearAllowedRepos => config_clear_allowed_repos(layout),
    }
}

fn handle_task(action: TaskCommand, layout: &StateLayout) -> Result<()> {
    ensure_state_layout(layout)?;
    match action {
        TaskCommand::Create(args) => task_create(layout, &args.ticket),
        TaskCommand::List => task_list(layout),
        TaskCommand::Show(args) => task_show(layout, &args.ticket),
    }
}

fn handle_worker(action: WorkerCommand, layout: &StateLayout) -> Result<()> {
    ensure_state_layout(layout)?;
    match action {
        WorkerCommand::Start(args) => worker_start(layout, args),
        WorkerCommand::Loop(args) => worker_loop(args),
    }
}

fn worker_start(layout: &StateLayout, args: WorkerStartArgs) -> Result<()> {
    if args.interval_seconds == 0 {
        bail!("Invalid --interval-seconds value: 0");
    }
    let _caffeinate = maybe_start_caffeinate();

    if args.once {
        run_worker_cycle(layout)?;
        return Ok(());
    }

    println!(
        "Worker started (interval: {}s). Press Ctrl+C to stop.",
        args.interval_seconds
    );

    loop {
        run_worker_cycle(layout)?;
        thread::sleep(Duration::from_secs(args.interval_seconds));
    }
}

fn run_worker_cycle(layout: &StateLayout) -> Result<()> {
    let timestamp = now_utc();
    match pick_next_pending_task(layout)? {
        None => {
            println!("[{timestamp}] No pending tasks.");
        }
        Some(task) => {
            println!(
                "[{timestamp}] Next pending task: {} (created {}, updated {})",
                task.ticket, task.created_at, task.updated_at
            );
            println!(
                "[{timestamp}] Suggested next step: codex-core agents task show {}",
                task.ticket
            );
        }
    }
    Ok(())
}

fn worker_loop(args: WorkerLoopArgs) -> Result<()> {
    let prompt = resolve_loop_prompt(&args)?;
    let cwd = args
        .cd
        .canonicalize()
        .with_context(|| format!("failed to resolve working directory {}", args.cd.display()))?;

    if !args.once && args.interval_seconds == 0 {
        bail!("Invalid --interval-seconds value: 0");
    }
    if let Some(max_iterations) = args.max_iterations
        && max_iterations == 0
    {
        bail!("Invalid --max-iterations value: 0");
    }
    let _caffeinate = maybe_start_caffeinate();

    println!("Loop started.");
    println!("  cwd: {}", cwd.display());
    println!("  stop phrase: {}", args.stop_phrase);
    if args.once {
        println!("  mode: once");
    } else if let Some(max_iterations) = args.max_iterations {
        println!("  max iterations: {}", max_iterations);
        println!("  interval: {}s", args.interval_seconds);
    } else {
        println!("  max iterations: unlimited");
        println!("  interval: {}s", args.interval_seconds);
    }

    let mut iteration: u64 = 0;
    loop {
        iteration += 1;
        println!("[loop {iteration}] Running codex exec...");
        let result = run_codex_exec_iteration(&cwd, &prompt, &args)
            .with_context(|| format!("codex exec failed on iteration {}", iteration))?;

        println!(
            "[loop {iteration}] Final message:\n{}",
            result.final_message
        );

        if !args.stop_phrase.is_empty() && result.final_message.contains(&args.stop_phrase) {
            println!(
                "[loop {iteration}] Stop phrase matched ({}). Stopping.",
                args.stop_phrase
            );
            break;
        }

        if args.once {
            println!("[loop {iteration}] --once set. Stopping.");
            break;
        }

        if let Some(max_iterations) = args.max_iterations
            && iteration >= max_iterations
        {
            println!("[loop {iteration}] Reached --max-iterations={max_iterations}. Stopping.");
            break;
        }

        thread::sleep(Duration::from_secs(args.interval_seconds));
    }

    Ok(())
}

fn maybe_start_caffeinate() -> Option<CaffeinateGuard> {
    #[cfg(target_os = "macos")]
    {
        let pid = std::process::id().to_string();
        let mut cmd = Command::new("caffeinate");
        cmd.arg("-dimsu");
        cmd.arg("-w");
        cmd.arg(pid);

        match cmd.spawn() {
            Ok(child) => {
                println!("caffeinate: enabled");
                Some(CaffeinateGuard { child })
            }
            Err(_) => {
                println!("caffeinate: unavailable; continuing without sleep prevention");
                None
            }
        }
    }

    #[cfg(not(target_os = "macos"))]
    {
        None
    }
}

fn task_create(layout: &StateLayout, ticket: &str) -> Result<()> {
    validate_ticket_key(ticket)?;
    let path = task_path(layout, ticket);
    if path.exists() {
        bail!("Task already exists: {ticket}");
    }

    let now = now_utc();
    let record = TaskRecord {
        ticket: ticket.to_string(),
        status: "pending".to_string(),
        created_at: now.clone(),
        updated_at: now,
        path,
    };
    write_task_file(&record)?;
    println!("Created task: {}", record.ticket);
    Ok(())
}

fn config_show(layout: &StateLayout, args: ConfigShowArgs) -> Result<()> {
    let config = load_agents_config(layout)?;
    if args.json {
        println!(
            "{}",
            serde_json::to_string_pretty(&config).context("failed to serialize agents config")?
        );
        return Ok(());
    }

    if config.allowed_repos.is_empty() {
        println!("allowed_repos=");
    } else {
        println!("allowed_repos={}", config.allowed_repos.join(","));
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

fn config_set_allowed_repos(layout: &StateLayout, args: ConfigSetAllowedReposArgs) -> Result<()> {
    let mut normalized = normalize_repo_filters(args.repos)?;
    normalized.sort();
    normalized.dedup();

    let mut config = load_agents_config(layout)?;
    config.allowed_repos = normalized.clone();
    save_agents_config(layout, &config)?;

    if normalized.is_empty() {
        println!("Set allowed_repos=");
    } else {
        println!("Set allowed_repos={}", normalized.join(","));
    }
    Ok(())
}

fn config_clear_allowed_repos(layout: &StateLayout) -> Result<()> {
    let mut config = load_agents_config(layout)?;
    config.allowed_repos.clear();
    save_agents_config(layout, &config)?;
    println!("Cleared allowed_repos");
    Ok(())
}

fn task_list(layout: &StateLayout) -> Result<()> {
    let mut tasks = load_tasks(layout)?;
    if tasks.is_empty() {
        println!("No tasks found.");
        return Ok(());
    }

    tasks.sort_by(|a, b| b.updated_at.cmp(&a.updated_at));
    println!("{:<24} {:<10} UPDATED_AT", "TICKET", "STATUS");
    for task in tasks {
        println!(
            "{:<24} {:<10} {}",
            task.ticket, task.status, task.updated_at
        );
    }
    Ok(())
}

fn task_show(layout: &StateLayout, ticket: &str) -> Result<()> {
    validate_ticket_key(ticket)?;
    let path = task_path(layout, ticket);
    if !path.exists() {
        bail!("Task not found: {ticket}");
    }

    let task = read_task_file(&path)?;
    println!("ticket: {}", task.ticket);
    println!("status: {}", task.status);
    println!("created_at: {}", task.created_at);
    println!("updated_at: {}", task.updated_at);
    println!("path: {}", task.path.display());
    Ok(())
}

fn pick_next_pending_task(layout: &StateLayout) -> Result<Option<TaskRecord>> {
    let tasks = load_tasks(layout)?;
    let mut pending: Vec<TaskRecord> = tasks
        .into_iter()
        .filter(|task| task.status == "pending" || task.status == "open")
        .collect();

    pending.sort_by(|a, b| a.updated_at.cmp(&b.updated_at));
    Ok(pending.into_iter().next())
}

fn load_tasks(layout: &StateLayout) -> Result<Vec<TaskRecord>> {
    if !layout.tasks_dir.exists() {
        return Ok(Vec::new());
    }

    let mut tasks = Vec::new();
    for entry in fs::read_dir(&layout.tasks_dir)
        .with_context(|| format!("failed to read {}", layout.tasks_dir.display()))?
    {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|value| value.to_str()) != Some("task") {
            continue;
        }
        tasks.push(read_task_file(&path)?);
    }
    Ok(tasks)
}

fn read_task_file(path: &Path) -> Result<TaskRecord> {
    let content =
        fs::read_to_string(path).with_context(|| format!("failed to read {}", path.display()))?;
    let mut ticket = None;
    let mut status = None;
    let mut created_at = None;
    let mut updated_at = None;

    for line in content.lines() {
        if let Some((key, value)) = line.split_once('=') {
            match key.trim() {
                "ticket" => ticket = Some(value.trim().to_string()),
                "status" => status = Some(value.trim().to_string()),
                "created_at" => created_at = Some(value.trim().to_string()),
                "updated_at" => updated_at = Some(value.trim().to_string()),
                _ => {}
            }
        }
    }

    Ok(TaskRecord {
        ticket: ticket.context("task file missing 'ticket'")?,
        status: status.context("task file missing 'status'")?,
        created_at: created_at.context("task file missing 'created_at'")?,
        updated_at: updated_at.context("task file missing 'updated_at'")?,
        path: path.to_path_buf(),
    })
}

fn write_task_file(task: &TaskRecord) -> Result<()> {
    let payload = format!(
        "ticket={}\nstatus={}\ncreated_at={}\nupdated_at={}\n",
        task.ticket, task.status, task.created_at, task.updated_at
    );
    fs::write(&task.path, payload)
        .with_context(|| format!("failed to write {}", task.path.display()))?;
    Ok(())
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

fn ensure_state_layout(layout: &StateLayout) -> Result<()> {
    fs::create_dir_all(&layout.tasks_dir)
        .with_context(|| format!("failed to create {}", layout.tasks_dir.display()))?;
    fs::create_dir_all(layout.root.join("repos"))
        .with_context(|| format!("failed to create {}", layout.root.join("repos").display()))?;
    fs::create_dir_all(layout.root.join("worktrees")).with_context(|| {
        format!(
            "failed to create {}",
            layout.root.join("worktrees").display()
        )
    })?;
    fs::create_dir_all(layout.root.join("reviews"))
        .with_context(|| format!("failed to create {}", layout.root.join("reviews").display()))?;
    if !layout.config_file.exists() {
        let config = AgentsConfig {
            state_version: 2,
            initialized_at: now_utc(),
            allowed_repos: Vec::new(),
        };
        save_agents_config(layout, &config)?;
    }
    Ok(())
}

fn resolve_state_layout() -> Result<StateLayout> {
    let root = if let Some(path) = env::var_os("CODEX_AGENTS_HOME") {
        let trimmed = path.to_string_lossy().trim().to_string();
        if trimmed.is_empty() {
            default_state_home()?
        } else {
            PathBuf::from(trimmed)
        }
    } else {
        default_state_home()?
    };

    Ok(StateLayout {
        tasks_dir: root.join("tasks"),
        config_file: root.join("config.json"),
        root,
    })
}

fn load_agents_config(layout: &StateLayout) -> Result<AgentsConfig> {
    let content = fs::read_to_string(&layout.config_file)
        .with_context(|| format!("failed to read {}", layout.config_file.display()))?;
    serde_json::from_str(&content)
        .with_context(|| format!("failed to parse {}", layout.config_file.display()))
}

fn save_agents_config(layout: &StateLayout, config: &AgentsConfig) -> Result<()> {
    let payload =
        serde_json::to_string_pretty(config).context("failed to serialize agents config")?;
    fs::write(&layout.config_file, payload)
        .with_context(|| format!("failed to write {}", layout.config_file.display()))?;
    Ok(())
}

fn list_available_repos() -> Result<Vec<AvailableRepo>> {
    let mut owners = Vec::new();
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

    let mut repos = Vec::new();
    for owner in owners {
        let output = run_gh_json(
            vec![
                "repo".to_string(),
                "list".to_string(),
                owner,
                "--limit".to_string(),
                "1000".to_string(),
                "--json".to_string(),
                "name,owner,isArchived,viewerPermission".to_string(),
            ],
            None,
        )?;
        let listed: Vec<ListedRepo> =
            serde_json::from_str(&output).context("failed to parse gh repo list response")?;
        repos.extend(
            listed
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
                }),
        );
    }

    repos.sort_by(|a, b| a.full_name.cmp(&b.full_name));
    repos.dedup_by(|a, b| a.full_name == b.full_name);
    Ok(repos)
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

fn resolve_loop_prompt(args: &WorkerLoopArgs) -> Result<String> {
    if let Some(path) = &args.prompt_file {
        let prompt = fs::read_to_string(path)
            .with_context(|| format!("failed to read prompt file {}", path.display()))?;
        let trimmed = prompt.trim().to_string();
        if trimmed.is_empty() {
            bail!("Prompt file is empty: {}", path.display());
        }
        return Ok(trimmed);
    }

    if let Some(prompt) = &args.prompt {
        let trimmed = prompt.trim().to_string();
        if trimmed.is_empty() {
            bail!("Prompt cannot be empty");
        }
        return Ok(trimmed);
    }

    bail!("Missing prompt. Provide a positional prompt or --prompt-file <FILE>.")
}

fn run_codex_exec_iteration(
    cwd: &Path,
    prompt: &str,
    args: &WorkerLoopArgs,
) -> Result<LoopIterationResult> {
    let output_path = unique_output_file_path();
    let mut cmd = Command::new("codex");
    cmd.current_dir(cwd);
    cmd.arg("exec");
    cmd.arg(prompt);
    cmd.arg("--json");
    cmd.arg("--output-last-message");
    cmd.arg(&output_path);

    if let Some(model) = &args.model {
        cmd.arg("--model");
        cmd.arg(model);
    }
    if args.full_auto {
        cmd.arg("--full-auto");
    }
    if args.dangerously_bypass_approvals_and_sandbox {
        cmd.arg("--dangerously-bypass-approvals-and-sandbox");
    }
    if args.skip_git_repo_check {
        cmd.arg("--skip-git-repo-check");
    }

    let output = cmd.output().context("failed to spawn codex executable")?;
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();

    if !output.status.success() {
        let status = output.status.code().unwrap_or(1);
        let stderr_trimmed = stderr.trim();
        if stderr_trimmed.is_empty() {
            bail!("codex exec exited with status {status}");
        }
        bail!("codex exec exited with status {status}: {stderr_trimmed}");
    }

    let final_message = fs::read_to_string(&output_path)
        .unwrap_or_default()
        .trim()
        .to_string();
    let _ = fs::remove_file(&output_path);
    let normalized_message = if final_message.is_empty() {
        "(Empty Codex response)".to_string()
    } else {
        final_message
    };

    Ok(LoopIterationResult {
        final_message: normalized_message,
    })
}

fn unique_output_file_path() -> PathBuf {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    env::temp_dir().join(format!(
        "codex-core-agents-last-message-{}-{nanos}.txt",
        std::process::id()
    ))
}

fn default_state_home() -> Result<PathBuf> {
    let home = env::var_os("HOME").context("HOME is not set")?;
    Ok(PathBuf::from(home).join(".codex").join("agents"))
}

fn task_path(layout: &StateLayout, ticket: &str) -> PathBuf {
    layout.tasks_dir.join(format!("{ticket}.task"))
}

fn now_utc() -> String {
    Utc::now().format("%Y-%m-%dT%H:%M:%SZ").to_string()
}
