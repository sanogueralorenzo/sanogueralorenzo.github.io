use super::StateLayout;
use anyhow::{Context, Result, bail};
use clap::{Args, Subcommand};
use std::fs;
use std::path::{Path, PathBuf};

#[derive(Subcommand, Debug)]
pub(super) enum TaskCommand {
    /// Create task from ticket key
    Create(TaskCreateArgs),
    /// List tracked tasks
    List,
    /// Show task details by ticket key
    Show(TaskShowArgs),
}

#[derive(Args, Debug)]
pub(super) struct TaskCreateArgs {
    pub ticket: String,
}

#[derive(Args, Debug)]
pub(super) struct TaskShowArgs {
    pub ticket: String,
}

#[derive(Clone, Debug)]
struct TaskRecord {
    ticket: String,
    status: String,
    created_at: String,
    updated_at: String,
    path: PathBuf,
}

pub(super) fn handle_task(action: TaskCommand, layout: &StateLayout) -> Result<()> {
    super::ensure_state_layout(layout)?;
    match action {
        TaskCommand::Create(args) => task_create(layout, &args.ticket),
        TaskCommand::List => task_list(layout),
        TaskCommand::Show(args) => task_show(layout, &args.ticket),
    }
}

fn task_create(layout: &StateLayout, ticket: &str) -> Result<()> {
    validate_ticket_key(ticket)?;
    let path = task_path(layout, ticket);
    if path.exists() {
        bail!("Task already exists: {ticket}");
    }

    let now = super::now_utc();
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
        println!("{:<24} {:<10} {}", task.ticket, task.status, task.updated_at);
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

pub(super) fn pick_next_pending_task(layout: &StateLayout) -> Result<Option<(String, String, String)>> {
    let tasks = load_tasks(layout)?;
    let mut pending: Vec<TaskRecord> = tasks
        .into_iter()
        .filter(|task| task.status == "pending" || task.status == "open")
        .collect();

    pending.sort_by(|a, b| a.updated_at.cmp(&b.updated_at));
    Ok(pending
        .into_iter()
        .next()
        .map(|task| (task.ticket, task.created_at, task.updated_at)))
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
    let content = fs::read_to_string(path)
        .with_context(|| format!("failed to read {}", path.display()))?;
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

fn task_path(layout: &StateLayout, ticket: &str) -> PathBuf {
    layout.tasks_dir.join(format!("{ticket}.task"))
}
