use super::StateLayout;
use anyhow::{Context, Result, bail};
use clap::{Args, Subcommand};
use std::env;
use std::path::{Path, PathBuf};
use std::process::{Child, Command};
use std::thread;
use std::time::Duration;

const DEFAULT_WORKER_INTERVAL_SECONDS: u64 = 30;

#[derive(Subcommand, Debug)]
pub(super) enum WorkerCommand {
    /// Start autonomous worker loop
    Start(WorkerStartArgs),
    /// Run a repeated loop using `codex exec`
    Loop(WorkerLoopArgs),
}

#[derive(Args, Debug)]
pub(super) struct WorkerStartArgs {
    /// Run exactly one worker cycle and exit
    #[arg(long)]
    pub once: bool,

    /// Polling interval for worker loop in seconds
    #[arg(long = "interval-seconds", default_value_t = DEFAULT_WORKER_INTERVAL_SECONDS)]
    pub interval_seconds: u64,
}

#[derive(Args, Debug)]
pub(super) struct WorkerLoopArgs {
    /// Prompt to run on each iteration (or use --prompt-file)
    pub prompt: Option<String>,

    /// Read prompt from file instead of positional prompt
    #[arg(long = "prompt-file", value_name = "FILE", conflicts_with = "prompt")]
    pub prompt_file: Option<PathBuf>,

    /// Working directory for codex exec
    #[arg(long = "cd", value_name = "DIR", default_value = ".")]
    pub cd: PathBuf,

    /// Polling interval for worker loop in seconds
    #[arg(long = "interval-seconds", default_value_t = DEFAULT_WORKER_INTERVAL_SECONDS)]
    pub interval_seconds: u64,

    /// Maximum number of iterations before stopping
    #[arg(long = "max-iterations")]
    pub max_iterations: Option<u64>,

    /// Stop loop when final message contains this text
    #[arg(long = "stop-phrase", default_value = "LOOP_DONE")]
    pub stop_phrase: String,

    /// Optional model override passed to codex
    #[arg(long)]
    pub model: Option<String>,

    /// Run exactly one worker cycle and exit
    #[arg(long)]
    pub once: bool,

    /// Pass --full-auto to codex exec
    #[arg(long)]
    pub full_auto: bool,

    /// Pass --dangerously-bypass-approvals-and-sandbox to codex exec
    #[arg(long = "dangerously-bypass-approvals-and-sandbox")]
    pub dangerously_bypass_approvals_and_sandbox: bool,

    /// Pass --skip-git-repo-check to codex exec
    #[arg(long)]
    pub skip_git_repo_check: bool,
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

pub(super) fn handle_worker(action: WorkerCommand, layout: &StateLayout) -> Result<()> {
    super::ensure_state_layout(layout)?;
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
    let timestamp = super::now_utc();
    match super::task::pick_next_pending_task(layout)? {
        None => {
            println!("[{timestamp}] No pending tasks.");
        }
        Some((ticket, created_at, updated_at)) => {
            println!(
                "[{timestamp}] Next pending task: {} (created {}, updated {})",
                ticket, created_at, updated_at
            );
            println!(
                "[{timestamp}] Suggested next step: codex-core agents task show {}",
                ticket
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

fn resolve_loop_prompt(args: &WorkerLoopArgs) -> Result<String> {
    if let Some(path) = &args.prompt_file {
        let prompt = std::fs::read_to_string(path)
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

    let final_message = std::fs::read_to_string(&output_path)
        .unwrap_or_default()
        .trim()
        .to_string();
    let _ = std::fs::remove_file(&output_path);
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
