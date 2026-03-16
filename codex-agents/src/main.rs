use anyhow::{Context, Result, bail};
use chrono::Utc;
use clap::{Args, Parser, Subcommand};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
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
