use anyhow::{Context, Result, bail};
use chrono::Utc;
use clap::{Args, Parser, Subcommand};
use serde_json::Value;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

const DEFAULT_WORKER_INTERVAL_SECONDS: u64 = 30;

#[derive(Parser, Debug)]
#[command(name = "codex-agents")]
#[command(about = "Track local tasks and run a basic worker loop")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Initialize local codex-agents configuration
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
}

#[derive(Subcommand, Debug)]
enum ConfigCommand {
    /// Initialize local codex-agents configuration
    Init,
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
    /// Run a Ralph-style loop using `codex exec`
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
    #[arg(long = "stop-phrase", default_value = "RALPH_DONE")]
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
    session_id: Option<String>,
}

fn run() -> Result<()> {
    let cli = Cli::parse();
    let layout = resolve_state_layout()?;

    match cli.command {
        Commands::Config { action } => handle_config(action, &layout),
        Commands::Task { action } => handle_task(action, &layout),
        Commands::Worker { action } => handle_worker(action, &layout),
    }
}

fn handle_config(action: ConfigCommand, layout: &StateLayout) -> Result<()> {
    match action {
        ConfigCommand::Init => {
            let already_initialized = layout.config_file.exists();
            ensure_state_layout(layout)?;
            if already_initialized {
                println!(
                    "codex-agents state already initialized at: {}",
                    layout.root.display()
                );
            } else {
                println!(
                    "Initialized codex-agents state at: {}",
                    layout.root.display()
                );
            }
            Ok(())
        }
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
                "[{timestamp}] Suggested next step: codex-agents task show {}",
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
    let mut session_id: Option<String> = None;
    loop {
        iteration += 1;
        println!("[loop {iteration}] Running codex exec...");
        let result = run_codex_exec_iteration(&cwd, &prompt, session_id.as_deref(), &args)
            .with_context(|| format!("codex exec failed on iteration {}", iteration))?;

        if session_id.is_none()
            && let Some(found) = result.session_id.clone()
        {
            println!("[loop {iteration}] Session: {found}");
            session_id = Some(found);
        }

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
    if !layout.config_file.exists() {
        let payload = format!("state_version=1\ninitialized_at={}\n", now_utc());
        fs::write(&layout.config_file, payload)
            .with_context(|| format!("failed to write {}", layout.config_file.display()))?;
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
        config_file: root.join("config.env"),
        root,
    })
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
    session_id: Option<&str>,
    args: &WorkerLoopArgs,
) -> Result<LoopIterationResult> {
    let output_path = unique_output_file_path();
    let mut cmd = Command::new("codex");
    cmd.current_dir(cwd);
    cmd.arg("exec");
    if let Some(existing_session_id) = session_id {
        cmd.arg("resume");
        cmd.arg(existing_session_id);
    }
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
    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
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
        session_id: parse_session_id_from_jsonl(&stdout),
    })
}

fn unique_output_file_path() -> PathBuf {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    env::temp_dir().join(format!(
        "codex-agents-last-message-{}-{nanos}.txt",
        std::process::id()
    ))
}

fn parse_session_id_from_jsonl(events: &str) -> Option<String> {
    for line in events.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let Ok(value) = serde_json::from_str::<Value>(trimmed) else {
            continue;
        };
        for key in [
            "thread_id",
            "threadId",
            "conversation_id",
            "conversationId",
            "session_id",
            "sessionId",
        ] {
            if let Some(found) = find_key_recursively(&value, key) {
                return Some(found);
            }
        }
    }
    None
}

fn find_key_recursively(value: &Value, key: &str) -> Option<String> {
    match value {
        Value::Object(map) => {
            if let Some(found) = map.get(key).and_then(Value::as_str) {
                return Some(found.to_string());
            }
            for child in map.values() {
                if let Some(found) = find_key_recursively(child, key) {
                    return Some(found);
                }
            }
            None
        }
        Value::Array(items) => {
            for item in items {
                if let Some(found) = find_key_recursively(item, key) {
                    return Some(found);
                }
            }
            None
        }
        _ => None,
    }
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

fn main() {
    if let Err(error) = run() {
        eprintln!("Error: {error}");
        std::process::exit(1);
    }
}
