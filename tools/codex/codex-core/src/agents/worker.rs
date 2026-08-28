use super::StateLayout;
use anyhow::{Context, Result, bail};
use clap::{Args, Subcommand};
use serde::Deserialize;
use serde_json::json;
use std::env;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Output, Stdio};
use std::thread;
use std::time::{Duration, Instant};

const DEFAULT_WORKER_INTERVAL_SECONDS: u64 = 30;
const DEFAULT_PRECEDENT_TIMEOUT_MS: u64 = 5_000;
const DEFAULT_PRECEDENT_VALIDATION_TIMEOUT_MS: u64 = 120_000;

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

    /// Opt in to Precedent context injection and outcome recording
    #[arg(long = "precedent-state-dir", value_name = "DIR")]
    pub precedent_state_dir: Option<PathBuf>,

    /// Scope passed to Precedent when ranking context
    #[arg(long = "precedent-scope", value_name = "SCOPE")]
    pub precedent_scope: Option<String>,

    /// Comma-separated changed files passed to Precedent when ranking context
    #[arg(long = "precedent-changed-files", value_name = "FILES")]
    pub precedent_changed_files: Option<String>,

    /// Optional validation command recorded as Precedent validation evidence after each codex exec
    #[arg(long = "precedent-validation-command", value_name = "COMMAND")]
    pub precedent_validation_command: Option<String>,

    /// Timeout for --precedent-validation-command in milliseconds
    #[arg(
        long = "precedent-validation-timeout-ms",
        default_value_t = DEFAULT_PRECEDENT_VALIDATION_TIMEOUT_MS
    )]
    pub precedent_validation_timeout_ms: u64,

    /// Precedent CLI entrypoint
    #[arg(
        long = "precedent-bin",
        value_name = "FILE",
        default_value = "precedent/bin/precedent.mjs"
    )]
    pub precedent_bin: PathBuf,

    /// Codex executable used by tests and advanced wrappers
    #[arg(
        long = "codex-bin",
        value_name = "FILE",
        default_value = "codex",
        hide = true
    )]
    pub codex_bin: PathBuf,
}

#[derive(Debug)]
struct LoopIterationResult {
    final_message: String,
}

#[derive(Debug)]
struct LoopPrecedentTurn {
    prompt: String,
    attempt_session_id: Option<String>,
    injected_precedent_ids: Vec<String>,
}

#[derive(Deserialize)]
struct PrecedentContextOutput {
    schema_version: String,
    #[serde(rename = "contextBlock")]
    context_block: Option<String>,
    #[serde(default)]
    injections: Vec<PrecedentContextInjection>,
}

#[derive(Deserialize)]
struct PrecedentContextInjection {
    id: String,
}

#[derive(Debug)]
struct PrecedentContext {
    context_block: Option<String>,
    injected_precedent_ids: Vec<String>,
}

#[derive(Deserialize)]
struct PrecedentRepairOutput {
    schema_version: String,
    #[serde(rename = "repairId")]
    repair_id: Option<String>,
    #[serde(rename = "repairBlock")]
    repair_block: Option<String>,
}

#[derive(Debug)]
struct PendingRepair {
    repair_id: Option<String>,
    repair_session_id: String,
    block: String,
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
    validate_worker_start_args(&args)?;
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

    validate_worker_loop_args(&args)?;
    let _caffeinate = maybe_start_caffeinate();

    print_worker_loop_start(&cwd, &args);

    let mut iteration: u64 = 0;
    let loop_run_id = uuid::Uuid::new_v4().to_string();
    let mut pending_repair: Option<PendingRepair> = None;
    loop {
        iteration += 1;
        let active_repair = pending_repair.take();
        let turn = prepare_precedent_turn(
            &cwd,
            &prompt,
            &args,
            &loop_run_id,
            iteration,
            active_repair.as_ref().map(|repair| repair.block.as_str()),
        );
        println!("[loop {iteration}] Running codex exec...");
        let diff_before = capture_precedent_diff_snapshot(&cwd);
        let result = match run_codex_exec_iteration(&cwd, &turn.prompt, &args) {
            Ok(result) => result,
            Err(error) => {
                if let Some(session_id) = turn.attempt_session_id.as_deref() {
                    run_and_record_precedent_diff(
                        &cwd,
                        &args,
                        session_id,
                        &turn.injected_precedent_ids,
                        diff_before.as_ref(),
                    );
                    record_precedent_outcome(
                        &cwd,
                        &args,
                        session_id,
                        &turn.injected_precedent_ids,
                        &prompt,
                        &error.to_string(),
                        false,
                        "codex_exec_failed",
                    );
                    if let Some(repair) = active_repair.as_ref() {
                        record_precedent_repair_after_retry(
                            &cwd,
                            &args,
                            session_id,
                            repair,
                            &turn.injected_precedent_ids,
                        );
                    }
                }
                return Err(error)
                    .with_context(|| format!("codex exec failed on iteration {}", iteration));
            }
        };
        let stop_matched =
            !args.stop_phrase.is_empty() && result.final_message.contains(&args.stop_phrase);

        if let Some(session_id) = turn.attempt_session_id.as_deref() {
            run_and_record_precedent_diff(
                &cwd,
                &args,
                session_id,
                &turn.injected_precedent_ids,
                diff_before.as_ref(),
            );
            run_and_record_precedent_validation(
                &cwd,
                &args,
                session_id,
                &turn.injected_precedent_ids,
            );
            record_precedent_outcome(
                &cwd,
                &args,
                session_id,
                &turn.injected_precedent_ids,
                &prompt,
                &result.final_message,
                stop_matched,
                if stop_matched { "success" } else { "failure" },
            );
            if let Some(repair) = active_repair.as_ref() {
                record_precedent_repair_after_retry(
                    &cwd,
                    &args,
                    session_id,
                    repair,
                    &turn.injected_precedent_ids,
                );
            }
        }

        println!(
            "[loop {iteration}] Final message:\n{}",
            result.final_message
        );

        if stop_matched {
            println!(
                "[loop {iteration}] Stop phrase matched ({}). Stopping.",
                args.stop_phrase
            );
            break;
        }

        if should_stop_after_iteration(iteration, &args) {
            break;
        }

        if let Some(session_id) = turn.attempt_session_id.as_deref() {
            let next_session_id = precedent_session_id(&loop_run_id, iteration + 1);
            pending_repair = fetch_precedent_repair_before_retry(
                &cwd,
                &args,
                session_id,
                &next_session_id,
                &turn.injected_precedent_ids,
                &prompt,
                &result.final_message,
                iteration,
            );
        }

        thread::sleep(Duration::from_secs(args.interval_seconds));
    }

    Ok(())
}

fn validate_worker_start_args(args: &WorkerStartArgs) -> Result<()> {
    if args.interval_seconds == 0 {
        bail!("Invalid --interval-seconds value: 0");
    }
    Ok(())
}

fn validate_worker_loop_args(args: &WorkerLoopArgs) -> Result<()> {
    if !args.once && args.interval_seconds == 0 {
        bail!("Invalid --interval-seconds value: 0");
    }
    if let Some(max_iterations) = args.max_iterations
        && max_iterations == 0
    {
        bail!("Invalid --max-iterations value: 0");
    }
    if args.precedent_validation_command.is_some() && args.precedent_validation_timeout_ms == 0 {
        bail!("Invalid --precedent-validation-timeout-ms value: 0");
    }
    Ok(())
}

fn print_worker_loop_start(cwd: &Path, args: &WorkerLoopArgs) {
    println!("Loop started.");
    println!("  cwd: {}", cwd.display());
    println!("  stop phrase: {}", args.stop_phrase);
    if args.precedent_state_dir.is_some() {
        println!("  precedent: enabled");
    }

    if args.once {
        println!("  mode: once");
        return;
    }

    let max_iterations = args
        .max_iterations
        .map(|value| value.to_string())
        .unwrap_or_else(|| "unlimited".to_string());
    println!("  max iterations: {max_iterations}");
    println!("  interval: {}s", args.interval_seconds);
}

fn should_stop_after_iteration(iteration: u64, args: &WorkerLoopArgs) -> bool {
    if args.once {
        println!("[loop {iteration}] --once set. Stopping.");
        return true;
    }

    if let Some(max_iterations) = args.max_iterations
        && iteration >= max_iterations
    {
        println!("[loop {iteration}] Reached --max-iterations={max_iterations}. Stopping.");
        return true;
    }

    false
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
    let mut cmd = Command::new(&args.codex_bin);
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

fn prepare_precedent_turn(
    cwd: &Path,
    prompt: &str,
    args: &WorkerLoopArgs,
    loop_run_id: &str,
    iteration: u64,
    repair_block: Option<&str>,
) -> LoopPrecedentTurn {
    if args.precedent_state_dir.is_none() {
        return LoopPrecedentTurn {
            prompt: prompt_with_precedent_blocks(prompt, repair_block, None),
            attempt_session_id: None,
            injected_precedent_ids: Vec::new(),
        };
    }

    let context_session_id = precedent_loop_session_id(loop_run_id);
    let attempt_session_id = precedent_session_id(loop_run_id, iteration);
    let mut injected_precedent_ids = Vec::new();
    let prompt = match fetch_precedent_context(cwd, args, &context_session_id, prompt) {
        Ok(context) => {
            injected_precedent_ids = context.injected_precedent_ids;
            prompt_with_precedent_blocks(prompt, repair_block, context.context_block.as_deref())
        }
        Err(error) => {
            eprintln!("[loop {iteration}] Precedent context unavailable: {error}");
            prompt_with_precedent_blocks(prompt, repair_block, None)
        }
    };

    LoopPrecedentTurn {
        prompt,
        attempt_session_id: Some(attempt_session_id),
        injected_precedent_ids,
    }
}

fn fetch_precedent_context(
    cwd: &Path,
    args: &WorkerLoopArgs,
    session_id: &str,
    prompt: &str,
) -> Result<PrecedentContext> {
    let state_dir = args
        .precedent_state_dir
        .as_ref()
        .context("precedent state dir is not configured")?;
    let mut cmd = precedent_command(cwd, &args.precedent_bin);
    let task_file = unique_temp_file_path("codex-core-agents-precedent-task", "md");
    std::fs::write(&task_file, prompt).with_context(|| {
        format!(
            "failed to write Precedent task file {}",
            task_file.display()
        )
    })?;
    cmd.arg("context");
    cmd.arg("--state-dir");
    cmd.arg(state_dir);
    cmd.arg("--task-file");
    cmd.arg(&task_file);
    cmd.arg("--session");
    cmd.arg(session_id);
    cmd.arg("--format");
    cmd.arg("json");
    if let Some(scope) = &args.precedent_scope
        && !scope.trim().is_empty()
    {
        cmd.arg("--scope");
        cmd.arg(scope);
    }
    if let Some(changed_files) = &args.precedent_changed_files
        && !changed_files.trim().is_empty()
    {
        cmd.arg("--changed-files");
        cmd.arg(changed_files);
    }

    let output = output_with_timeout(
        cmd,
        None,
        Duration::from_millis(DEFAULT_PRECEDENT_TIMEOUT_MS),
    );
    let _ = std::fs::remove_file(&task_file);
    let output = output.context("context command failed")?;
    if !output.status.success() {
        bail!(
            "context exited with status {}{}",
            output.status.code().unwrap_or(1),
            stderr_suffix(&output)
        );
    }

    let parsed: PrecedentContextOutput =
        serde_json::from_slice(&output.stdout).context("context returned invalid JSON")?;
    if parsed.schema_version != "precedent.context.v1" {
        bail!(
            "context returned unsupported schema {}",
            parsed.schema_version
        );
    }
    Ok(PrecedentContext {
        context_block: parsed
            .context_block
            .filter(|block| !block.trim().is_empty()),
        injected_precedent_ids: parsed
            .injections
            .into_iter()
            .map(|injection| injection.id.trim().to_string())
            .filter(|id| !id.is_empty())
            .collect(),
    })
}

fn fetch_precedent_repair_before_retry(
    cwd: &Path,
    args: &WorkerLoopArgs,
    session_id: &str,
    next_session_id: &str,
    injected_precedent_ids: &[String],
    task: &str,
    final_message: &str,
    retry: u64,
) -> Option<PendingRepair> {
    match try_fetch_precedent_repair_before_retry(
        cwd,
        args,
        session_id,
        next_session_id,
        injected_precedent_ids,
        task,
        final_message,
        retry,
    ) {
        Ok(repair_block) => repair_block,
        Err(error) => {
            eprintln!("[precedent {session_id}] repair unavailable: {error}");
            None
        }
    }
}

fn try_fetch_precedent_repair_before_retry(
    cwd: &Path,
    args: &WorkerLoopArgs,
    session_id: &str,
    next_session_id: &str,
    injected_precedent_ids: &[String],
    task: &str,
    final_message: &str,
    retry: u64,
) -> Result<Option<PendingRepair>> {
    let state_dir = args
        .precedent_state_dir
        .as_ref()
        .context("precedent state dir is not configured")?;
    let mut cmd = precedent_command(cwd, &args.precedent_bin);
    cmd.arg("hook");
    cmd.arg("--state-dir");
    cmd.arg(state_dir);
    cmd.arg("--json");
    let payload = json!({
        "schema_version": "precedent.v1",
        "hook": "repair.before_retry",
        "sessionId": session_id,
        "nextSessionId": next_session_id,
        "task": task,
        "finalMessage": final_message,
        "scope": args.precedent_scope.as_deref().unwrap_or(""),
        "changedFiles": precedent_changed_files(args),
        "retry": retry,
        "attributedPrecedents": injected_precedent_ids,
    });
    let stdin = serde_json::to_string(&payload).context("failed to serialize Precedent repair")?;
    let output = output_with_timeout(
        cmd,
        Some(&stdin),
        Duration::from_millis(DEFAULT_PRECEDENT_TIMEOUT_MS),
    )
    .context("repair hook command failed")?;
    if !output.status.success() {
        bail!(
            "repair hook exited with status {}{}",
            output.status.code().unwrap_or(1),
            stderr_suffix(&output)
        );
    }

    let parsed: PrecedentRepairOutput =
        serde_json::from_slice(&output.stdout).context("repair hook returned invalid JSON")?;
    if parsed.schema_version != "precedent.repair.v1" {
        bail!(
            "repair hook returned unsupported schema {}",
            parsed.schema_version
        );
    }

    Ok(parsed
        .repair_block
        .map(|block| block.trim().to_string())
        .filter(|block| !block.is_empty())
        .map(|block| PendingRepair {
            repair_id: parsed
                .repair_id
                .map(|id| id.trim().to_string())
                .filter(|id| !id.is_empty()),
            repair_session_id: session_id.to_string(),
            block,
        }))
}

fn record_precedent_outcome(
    cwd: &Path,
    args: &WorkerLoopArgs,
    session_id: &str,
    injected_precedent_ids: &[String],
    task: &str,
    final_message: &str,
    success: bool,
    status: &str,
) {
    if let Err(error) = try_record_precedent_outcome(
        cwd,
        args,
        session_id,
        injected_precedent_ids,
        task,
        final_message,
        success,
        status,
    ) {
        eprintln!("[precedent {session_id}] outcome unavailable: {error}");
    }
}

fn record_precedent_repair_after_retry(
    cwd: &Path,
    args: &WorkerLoopArgs,
    session_id: &str,
    repair: &PendingRepair,
    injected_precedent_ids: &[String],
) {
    if repair.repair_id.is_none() {
        return;
    }

    if let Err(error) = try_record_precedent_repair_after_retry(
        cwd,
        args,
        session_id,
        repair,
        injected_precedent_ids,
    ) {
        eprintln!("[precedent {session_id}] repair receipt unavailable: {error}");
    }
}

fn try_record_precedent_repair_after_retry(
    cwd: &Path,
    args: &WorkerLoopArgs,
    session_id: &str,
    repair: &PendingRepair,
    injected_precedent_ids: &[String],
) -> Result<()> {
    let state_dir = args
        .precedent_state_dir
        .as_ref()
        .context("precedent state dir is not configured")?;
    let mut cmd = precedent_command(cwd, &args.precedent_bin);
    cmd.arg("hook");
    cmd.arg("--state-dir");
    cmd.arg(state_dir);
    cmd.arg("--json");
    let payload = json!({
        "schema_version": "precedent.v1",
        "hook": "repair.after_retry",
        "sessionId": session_id,
        "repairId": repair.repair_id.as_deref().unwrap_or(""),
        "repairSessionId": repair.repair_session_id,
        "attributedPrecedents": injected_precedent_ids,
    });
    let stdin =
        serde_json::to_string(&payload).context("failed to serialize Precedent repair receipt")?;
    let output = output_with_timeout(
        cmd,
        Some(&stdin),
        Duration::from_millis(DEFAULT_PRECEDENT_TIMEOUT_MS),
    )
    .context("repair receipt hook command failed")?;
    if !output.status.success() {
        bail!(
            "repair receipt hook exited with status {}{}",
            output.status.code().unwrap_or(1),
            stderr_suffix(&output)
        );
    }

    Ok(())
}

fn run_and_record_precedent_validation(
    cwd: &Path,
    args: &WorkerLoopArgs,
    session_id: &str,
    injected_precedent_ids: &[String],
) {
    let Some(command) = args.precedent_validation_command.as_deref() else {
        return;
    };
    if command.trim().is_empty() {
        return;
    }

    match run_precedent_validation_command(cwd, command, args.precedent_validation_timeout_ms) {
        Ok(result) => {
            if let Err(error) =
                record_precedent_validation(cwd, args, session_id, injected_precedent_ids, result)
            {
                eprintln!("[precedent {session_id}] validation unavailable: {error}");
            }
        }
        Err(error) => {
            eprintln!("[precedent {session_id}] validation command unavailable: {error}");
        }
    }
}

struct PrecedentValidationResult {
    command: String,
    exit_code: i32,
    duration_ms: u128,
    stdout: String,
    stderr: String,
}

#[derive(Debug)]
struct PrecedentDiffSnapshot {
    fingerprint: Vec<u8>,
    summary: PrecedentDiffResult,
}

#[derive(Debug)]
struct PrecedentDiffResult {
    changed_files: Vec<String>,
    lines_added: u64,
    lines_deleted: u64,
}

#[derive(Debug)]
struct GitStatusFile {
    status_x: char,
    status_y: char,
    path: String,
}

fn run_and_record_precedent_diff(
    cwd: &Path,
    args: &WorkerLoopArgs,
    session_id: &str,
    injected_precedent_ids: &[String],
    before: Option<&PrecedentDiffSnapshot>,
) {
    let Some(before) = before else {
        return;
    };

    match collect_git_diff_snapshot(cwd) {
        Ok(Some(after)) if after.fingerprint != before.fingerprint => {
            if let Err(error) =
                record_precedent_diff(cwd, args, session_id, injected_precedent_ids, after.summary)
            {
                eprintln!("[precedent {session_id}] diff unavailable: {error}");
            }
        }
        Ok(Some(_)) | Ok(None) => {}
        Err(error) => {
            eprintln!("[precedent {session_id}] diff unavailable: {error}");
        }
    }
}

fn capture_precedent_diff_snapshot(cwd: &Path) -> Option<PrecedentDiffSnapshot> {
    match collect_git_diff_snapshot(cwd) {
        Ok(snapshot) => snapshot,
        Err(error) => {
            eprintln!("[precedent] diff snapshot unavailable: {error}");
            None
        }
    }
}

fn collect_git_diff_snapshot(cwd: &Path) -> Result<Option<PrecedentDiffSnapshot>> {
    if !is_git_worktree(cwd)? {
        return Ok(None);
    }

    let status_files = git_status_files(cwd)?;
    let (lines_added, lines_deleted, numstat_files) = git_diff_numstat(cwd)?;
    let mut changed_files = Vec::new();
    for file in &status_files {
        push_unique(&mut changed_files, file.path.clone());
    }
    for file in &numstat_files {
        push_unique(&mut changed_files, file.clone());
    }
    changed_files.sort();

    let mut fingerprint = Vec::new();
    fingerprint.extend(
        git_output(
            cwd,
            &["status", "--porcelain=v1", "-z", "--untracked-files=all"],
        )?
        .stdout,
    );
    fingerprint.extend(git_output(cwd, &["diff", "--binary", "HEAD", "--"])?.stdout);
    fingerprint.extend(git_output(cwd, &["diff", "--cached", "--binary", "HEAD", "--"])?.stdout);
    for file in status_files
        .iter()
        .filter(|file| file.status_x == '?' && file.status_y == '?')
    {
        let path = cwd.join(&file.path);
        if let Ok(metadata) = std::fs::metadata(&path) {
            fingerprint.extend(file.path.as_bytes());
            fingerprint.extend(metadata.len().to_string().as_bytes());
            if let Ok(modified) = metadata.modified()
                && let Ok(duration) = modified.duration_since(std::time::UNIX_EPOCH)
            {
                fingerprint.extend(duration.as_nanos().to_string().as_bytes());
            }
        }
    }

    Ok(Some(PrecedentDiffSnapshot {
        fingerprint,
        summary: PrecedentDiffResult {
            changed_files,
            lines_added,
            lines_deleted,
        },
    }))
}

fn is_git_worktree(cwd: &Path) -> Result<bool> {
    let output = git_output(cwd, &["rev-parse", "--is-inside-work-tree"])?;
    Ok(output.status.success() && String::from_utf8_lossy(&output.stdout).trim() == "true")
}

fn git_status_files(cwd: &Path) -> Result<Vec<GitStatusFile>> {
    let output = git_output(
        cwd,
        &["status", "--porcelain=v1", "-z", "--untracked-files=all"],
    )?;
    if !output.status.success() {
        bail!(
            "git status exited with status {}{}",
            output.status.code().unwrap_or(1),
            stderr_suffix(&output)
        );
    }

    Ok(parse_git_status_files(&output.stdout))
}

fn git_diff_numstat(cwd: &Path) -> Result<(u64, u64, Vec<String>)> {
    let mut output = git_output(cwd, &["diff", "--numstat", "HEAD", "--"])?;
    if !output.status.success() {
        output = git_output(cwd, &["diff", "--numstat", "--"])?;
    }
    if !output.status.success() {
        bail!(
            "git diff --numstat exited with status {}{}",
            output.status.code().unwrap_or(1),
            stderr_suffix(&output)
        );
    }

    let text = String::from_utf8_lossy(&output.stdout);
    let mut lines_added = 0;
    let mut lines_deleted = 0;
    let mut files = Vec::new();

    for line in text.lines() {
        let mut parts = line.splitn(3, '\t');
        let added = parts.next().unwrap_or("");
        let deleted = parts.next().unwrap_or("");
        let file = parts.next().unwrap_or("").trim();
        if let Ok(value) = added.parse::<u64>() {
            lines_added += value;
        }
        if let Ok(value) = deleted.parse::<u64>() {
            lines_deleted += value;
        }
        if !file.is_empty() {
            push_unique(&mut files, file.to_string());
        }
    }

    Ok((lines_added, lines_deleted, files))
}

fn git_output(cwd: &Path, args: &[&str]) -> Result<Output> {
    Command::new("git")
        .current_dir(cwd)
        .args(args)
        .output()
        .context("failed to spawn git")
}

fn parse_git_status_files(stdout: &[u8]) -> Vec<GitStatusFile> {
    let mut files = Vec::new();
    let mut index = 0;

    while index + 3 <= stdout.len() {
        let status_x = stdout[index] as char;
        let status_y = stdout[index + 1] as char;
        index += 3;
        let Some(end) = stdout[index..].iter().position(|byte| *byte == 0) else {
            break;
        };
        let path = String::from_utf8_lossy(&stdout[index..index + end]).to_string();
        index += end + 1;

        if status_x == 'R' || status_x == 'C' || status_y == 'R' || status_y == 'C' {
            if let Some(old_path_end) = stdout[index..].iter().position(|byte| *byte == 0) {
                index += old_path_end + 1;
            }
        }

        if !path.trim().is_empty() {
            files.push(GitStatusFile {
                status_x,
                status_y,
                path,
            });
        }
    }

    files
}

fn push_unique(values: &mut Vec<String>, value: String) {
    if !values.iter().any(|existing| existing == &value) {
        values.push(value);
    }
}

fn run_precedent_validation_command(
    cwd: &Path,
    command: &str,
    timeout_ms: u64,
) -> Result<PrecedentValidationResult> {
    let started = Instant::now();
    let mut cmd = shell_command(command);
    cmd.current_dir(cwd);
    let output = output_with_timeout(cmd, None, Duration::from_millis(timeout_ms))?;
    Ok(PrecedentValidationResult {
        command: command.to_string(),
        exit_code: output.status.code().unwrap_or(1),
        duration_ms: started.elapsed().as_millis(),
        stdout: String::from_utf8_lossy(&output.stdout).to_string(),
        stderr: String::from_utf8_lossy(&output.stderr).to_string(),
    })
}

fn record_precedent_diff(
    cwd: &Path,
    args: &WorkerLoopArgs,
    session_id: &str,
    injected_precedent_ids: &[String],
    result: PrecedentDiffResult,
) -> Result<()> {
    let state_dir = args
        .precedent_state_dir
        .as_ref()
        .context("precedent state dir is not configured")?;
    let mut cmd = precedent_command(cwd, &args.precedent_bin);
    cmd.arg("hook");
    cmd.arg("--state-dir");
    cmd.arg(state_dir);
    cmd.arg("--json");
    let payload = json!({
        "schema_version": "precedent.v1",
        "hook": "diff.after_edit",
        "sessionId": session_id,
        "changedFiles": result.changed_files,
        "linesAdded": result.lines_added,
        "linesDeleted": result.lines_deleted,
        "attributedPrecedents": injected_precedent_ids,
    });
    let stdin = serde_json::to_string(&payload).context("failed to serialize Precedent diff")?;
    let output = output_with_timeout(
        cmd,
        Some(&stdin),
        Duration::from_millis(DEFAULT_PRECEDENT_TIMEOUT_MS),
    )
    .context("diff hook command failed")?;
    if !output.status.success() {
        bail!(
            "diff hook exited with status {}{}",
            output.status.code().unwrap_or(1),
            stderr_suffix(&output)
        );
    }

    Ok(())
}

fn record_precedent_validation(
    cwd: &Path,
    args: &WorkerLoopArgs,
    session_id: &str,
    injected_precedent_ids: &[String],
    result: PrecedentValidationResult,
) -> Result<()> {
    let state_dir = args
        .precedent_state_dir
        .as_ref()
        .context("precedent state dir is not configured")?;
    let mut cmd = precedent_command(cwd, &args.precedent_bin);
    cmd.arg("hook");
    cmd.arg("--state-dir");
    cmd.arg(state_dir);
    cmd.arg("--json");
    let payload = json!({
        "schema_version": "precedent.v1",
        "hook": "validation.after_run",
        "sessionId": session_id,
        "command": result.command,
        "exitCode": result.exit_code,
        "durationMs": result.duration_ms,
        "stdout": result.stdout,
        "stderr": result.stderr,
        "attributedPrecedents": injected_precedent_ids,
    });
    let stdin =
        serde_json::to_string(&payload).context("failed to serialize Precedent validation")?;
    let output = output_with_timeout(
        cmd,
        Some(&stdin),
        Duration::from_millis(DEFAULT_PRECEDENT_TIMEOUT_MS),
    )
    .context("validation hook command failed")?;
    if !output.status.success() {
        bail!(
            "validation hook exited with status {}{}",
            output.status.code().unwrap_or(1),
            stderr_suffix(&output)
        );
    }

    Ok(())
}

fn try_record_precedent_outcome(
    cwd: &Path,
    args: &WorkerLoopArgs,
    session_id: &str,
    injected_precedent_ids: &[String],
    task: &str,
    final_message: &str,
    success: bool,
    status: &str,
) -> Result<()> {
    let state_dir = args
        .precedent_state_dir
        .as_ref()
        .context("precedent state dir is not configured")?;
    let mut cmd = precedent_command(cwd, &args.precedent_bin);
    cmd.arg("hook");
    cmd.arg("--state-dir");
    cmd.arg(state_dir);
    cmd.arg("--json");
    let payload = json!({
        "schema_version": "precedent.v1",
        "hook": "outcome.after_task",
        "sessionId": session_id,
        "success": success,
        "status": status,
        "task": task,
        "scope": args.precedent_scope.as_deref().unwrap_or(""),
        "changedFiles": precedent_changed_files(args),
        "retries": 0,
        "tokenEstimate": null,
        "notes": final_message,
        "attributedPrecedents": injected_precedent_ids,
    });
    let stdin = serde_json::to_string(&payload).context("failed to serialize Precedent outcome")?;
    let output = output_with_timeout(
        cmd,
        Some(&stdin),
        Duration::from_millis(DEFAULT_PRECEDENT_TIMEOUT_MS),
    )
    .context("outcome hook command failed")?;
    if !output.status.success() {
        bail!(
            "outcome hook exited with status {}{}",
            output.status.code().unwrap_or(1),
            stderr_suffix(&output)
        );
    }

    Ok(())
}

fn precedent_command(cwd: &Path, precedent_bin: &Path) -> Command {
    let mut cmd = if precedent_bin == Path::new("precedent/bin/precedent.mjs") {
        let mut command = Command::new("node");
        command.arg(precedent_bin);
        command
    } else {
        Command::new(precedent_bin)
    };
    cmd.current_dir(cwd);
    cmd
}

fn prompt_with_precedent_context(prompt: &str, context_block: Option<&str>) -> String {
    match context_block
        .map(str::trim)
        .filter(|block| !block.is_empty())
    {
        Some(block) => format!("{block}\n\n{prompt}"),
        None => prompt.to_string(),
    }
}

fn prompt_with_precedent_blocks(
    prompt: &str,
    repair_block: Option<&str>,
    context_block: Option<&str>,
) -> String {
    let blocks: Vec<&str> = [repair_block, context_block]
        .into_iter()
        .flatten()
        .map(str::trim)
        .filter(|block| !block.is_empty())
        .collect();
    if blocks.is_empty() {
        return prompt.to_string();
    }

    format!("{}\n\n{prompt}", blocks.join("\n\n"))
}

fn precedent_loop_session_id(loop_run_id: &str) -> String {
    format!("codex-core-worker-loop-{loop_run_id}")
}

fn precedent_session_id(loop_run_id: &str, iteration: u64) -> String {
    format!("codex-core-worker-loop-{loop_run_id}-{iteration}")
}

fn precedent_changed_files(args: &WorkerLoopArgs) -> Vec<String> {
    args.precedent_changed_files
        .as_deref()
        .unwrap_or("")
        .split(',')
        .map(str::trim)
        .filter(|file| !file.is_empty())
        .map(ToString::to_string)
        .collect()
}

fn shell_command(command: &str) -> Command {
    #[cfg(target_os = "windows")]
    {
        let mut cmd = Command::new("cmd");
        cmd.arg("/C");
        cmd.arg(command);
        cmd
    }

    #[cfg(not(target_os = "windows"))]
    {
        let mut cmd = Command::new("sh");
        cmd.arg("-c");
        cmd.arg(command);
        cmd
    }
}

fn output_with_timeout(
    mut command: Command,
    stdin: Option<&str>,
    timeout: Duration,
) -> Result<Output> {
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());
    if stdin.is_some() {
        command.stdin(Stdio::piped());
    }

    let mut child = command.spawn().context("failed to spawn command")?;
    if let Some(stdin_text) = stdin
        && let Some(mut child_stdin) = child.stdin.take()
    {
        child_stdin
            .write_all(stdin_text.as_bytes())
            .context("failed to write command stdin")?;
    }

    let deadline = Instant::now() + timeout;
    loop {
        if child
            .try_wait()
            .context("failed waiting for command")?
            .is_some()
        {
            return child
                .wait_with_output()
                .context("failed to read command output");
        }
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            bail!("timed out after {}ms", timeout.as_millis());
        }
        thread::sleep(Duration::from_millis(10));
    }
}

fn stderr_suffix(output: &Output) -> String {
    let stderr = String::from_utf8_lossy(&output.stderr);
    let trimmed = stderr.trim();
    if trimmed.is_empty() {
        String::new()
    } else {
        format!(": {trimmed}")
    }
}

fn unique_output_file_path() -> PathBuf {
    unique_temp_file_path("codex-core-agents-last-message", "txt")
}

fn unique_temp_file_path(prefix: &str, extension: &str) -> PathBuf {
    let nanos = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    env::temp_dir().join(format!(
        "{prefix}-{}-{nanos}.{extension}",
        std::process::id(),
    ))
}

#[cfg(test)]
mod tests {
    use super::{
        DEFAULT_PRECEDENT_VALIDATION_TIMEOUT_MS, WorkerLoopArgs, precedent_loop_session_id,
        precedent_session_id, prompt_with_precedent_blocks, prompt_with_precedent_context,
        resolve_loop_prompt, validate_worker_loop_args, worker_loop,
    };
    use std::env;
    use std::fs;
    use std::os::unix::fs::PermissionsExt;
    use std::path::PathBuf;
    use std::process::Command;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn base_args() -> WorkerLoopArgs {
        WorkerLoopArgs {
            prompt: Some("loop prompt".to_string()),
            prompt_file: None,
            cd: PathBuf::from("."),
            interval_seconds: 30,
            max_iterations: None,
            stop_phrase: "LOOP_DONE".to_string(),
            model: None,
            once: false,
            full_auto: false,
            dangerously_bypass_approvals_and_sandbox: false,
            skip_git_repo_check: false,
            precedent_state_dir: None,
            precedent_scope: None,
            precedent_changed_files: None,
            precedent_validation_command: None,
            precedent_validation_timeout_ms: DEFAULT_PRECEDENT_VALIDATION_TIMEOUT_MS,
            precedent_bin: PathBuf::from("precedent/bin/precedent.mjs"),
            codex_bin: PathBuf::from("codex"),
        }
    }

    #[test]
    fn validate_worker_loop_args_rejects_zero_interval() {
        let mut args = base_args();
        args.interval_seconds = 0;
        let error = validate_worker_loop_args(&args).unwrap_err();
        assert!(
            error
                .to_string()
                .contains("Invalid --interval-seconds value: 0")
        );
    }

    #[test]
    fn validate_worker_loop_args_rejects_zero_precedent_validation_timeout() {
        let mut args = base_args();
        args.precedent_validation_command = Some("cargo test".to_string());
        args.precedent_validation_timeout_ms = 0;
        let error = validate_worker_loop_args(&args).unwrap_err();
        assert!(
            error
                .to_string()
                .contains("Invalid --precedent-validation-timeout-ms value: 0")
        );
    }

    #[test]
    fn resolve_loop_prompt_reads_prompt_file() {
        let file_name = format!(
            "codex-core-agents-test-{}.md",
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        );
        let path = env::temp_dir().join(file_name);
        fs::write(&path, "  prompt from file  \n").unwrap();

        let mut args = base_args();
        args.prompt = None;
        args.prompt_file = Some(path.clone());

        let prompt = resolve_loop_prompt(&args).unwrap();
        assert_eq!(prompt, "prompt from file");

        let _ = fs::remove_file(path);
    }

    #[test]
    fn prompt_wrapping_preserves_prompt_without_context() {
        assert_eq!(
            prompt_with_precedent_context("original prompt", None),
            "original prompt"
        );
        assert_eq!(
            prompt_with_precedent_context("original prompt", Some("   \n ")),
            "original prompt"
        );
    }

    #[test]
    fn prompt_wrapping_prepends_context_once() {
        assert_eq!(
            prompt_with_precedent_context(
                "original prompt",
                Some("Precedent:\n- Run focused tests.")
            ),
            "Precedent:\n- Run focused tests.\n\noriginal prompt"
        );
    }

    #[test]
    fn prompt_wrapping_prepends_repair_before_context() {
        assert_eq!(
            prompt_with_precedent_blocks(
                "original prompt",
                Some("Precedent repair:\n- Fix bad path."),
                Some("Precedent:\n- Run focused tests."),
            ),
            "Precedent repair:\n- Fix bad path.\n\nPrecedent:\n- Run focused tests.\n\noriginal prompt"
        );
    }

    #[test]
    fn precedent_session_ids_are_stable_and_distinct() {
        assert_eq!(
            precedent_loop_session_id("run-1"),
            "codex-core-worker-loop-run-1"
        );
        assert_eq!(
            precedent_session_id("run-1", 1),
            "codex-core-worker-loop-run-1-1"
        );
        assert_ne!(
            precedent_loop_session_id("run-1"),
            precedent_session_id("run-1", 1)
        );
        assert_ne!(
            precedent_session_id("run-1", 1),
            precedent_session_id("run-1", 2)
        );
    }

    #[test]
    fn worker_loop_injects_precedent_context_and_records_outcome() {
        let dir = temp_test_dir("precedent-worker-inject");
        let codex_bin = dir.join("fake-codex.sh");
        let precedent_bin = dir.join("fake-precedent.sh");
        let prompt_capture = dir.join("prompt.txt");
        let context_capture = dir.join("context-args.txt");
        let hook_capture = dir.join("hook.json");
        let state_dir = dir.join("state");
        fs::create_dir_all(&state_dir).unwrap();
        write_executable(
            &codex_bin,
            &format!(
                r#"#!/bin/sh
out=""
prompt=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "exec" ]; then
    shift
    prompt="$1"
    shift
    continue
  fi
  if [ "$1" = "--output-last-message" ]; then
    shift
    out="$1"
    shift
    continue
  fi
  shift
done
printf '%s' "$prompt" > '{}'
printf '%s' 'LOOP_DONE from fake codex' > "$out"
"#,
                prompt_capture.display()
            ),
        );
        write_executable(
            &precedent_bin,
            &format!(
                r#"#!/bin/sh
if [ "$1" = "context" ]; then
  printf '%s\n' "$*" > '{}'
  printf '%s\n' '{{"schema_version":"precedent.context.v1","contextBlock":"Precedent:\n- Use repo lesson.","injections":[{{"id":"prec_repo_lesson"}}]}}'
  exit 0
fi
if [ "$1" = "hook" ]; then
  cat > '{}'
  printf '%s\n' '{{"ok":true}}'
  exit 0
fi
exit 2
"#,
                context_capture.display(),
                hook_capture.display()
            ),
        );

        let mut args = base_args();
        args.prompt = Some("ship the feature".to_string());
        args.cd = dir.clone();
        args.once = true;
        args.precedent_state_dir = Some(state_dir);
        args.precedent_scope = Some("feature:webhooks".to_string());
        args.precedent_changed_files =
            Some("features/webhooks/providers/stripe.ts,features/webhooks/schema.ts".to_string());
        args.precedent_bin = precedent_bin;
        args.codex_bin = codex_bin;

        worker_loop(args).unwrap();

        let prompt = fs::read_to_string(prompt_capture).unwrap();
        assert!(prompt.starts_with("Precedent:\n- Use repo lesson.\n\nship the feature"));
        let context_args = fs::read_to_string(context_capture).unwrap();
        assert!(context_args.contains("--session codex-core-worker-loop-"));
        assert!(!context_args.contains("-1 --format"));
        assert!(context_args.contains("--changed-files"));
        assert!(
            context_args
                .contains("features/webhooks/providers/stripe.ts,features/webhooks/schema.ts")
        );
        let hook = fs::read_to_string(hook_capture).unwrap();
        assert!(hook.contains(r#""hook":"outcome.after_task""#));
        assert!(hook.contains(r#""success":true"#));
        assert!(hook.contains(r#""task":"ship the feature""#));
        assert!(hook.contains(r#""scope":"feature:webhooks""#));
        assert!(hook.contains(r#""changedFiles":["features/webhooks/providers/stripe.ts","features/webhooks/schema.ts"]"#));
        assert!(hook.contains(r#""attributedPrecedents":["prec_repo_lesson"]"#));
        assert!(hook.contains(r#""sessionId":"codex-core-worker-loop-"#));
        assert!(hook.contains(r#"-1""#));

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn worker_loop_suppresses_repeated_precedent_context_with_stable_loop_session() {
        let dir = temp_test_dir("precedent-worker-stable-context");
        let codex_bin = dir.join("fake-codex.sh");
        let precedent_bin = dir.join("fake-precedent.sh");
        let prompt_capture = dir.join("prompts.txt");
        let context_sessions = dir.join("context-sessions.txt");
        let hooks_capture = dir.join("hooks.jsonl");
        let codex_counter = dir.join("codex-count.txt");
        let precedent_counter = dir.join("precedent-count.txt");
        let state_dir = dir.join("state");
        fs::create_dir_all(&state_dir).unwrap();
        write_executable(
            &codex_bin,
            &format!(
                r#"#!/bin/sh
out=""
prompt=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "exec" ]; then
    shift
    prompt="$1"
    shift
    continue
  fi
  if [ "$1" = "--output-last-message" ]; then
    shift
    out="$1"
    shift
    continue
  fi
  shift
done
printf '%s\n---prompt---\n' "$prompt" >> '{}'
count=0
if [ -f '{}' ]; then
  count=$(cat '{}')
fi
count=$((count + 1))
printf '%s' "$count" > '{}'
if [ "$count" -eq 1 ]; then
  printf '%s' 'keep going' > "$out"
else
  printf '%s' 'LOOP_DONE from fake codex' > "$out"
fi
"#,
                prompt_capture.display(),
                codex_counter.display(),
                codex_counter.display(),
                codex_counter.display()
            ),
        );
        write_executable(
            &precedent_bin,
            &format!(
                r#"#!/bin/sh
if [ "$1" = "context" ]; then
  session=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "--session" ]; then
      shift
      session="$1"
      shift
      continue
    fi
    shift
  done
  printf '%s\n' "$session" >> '{}'
  count=0
  if [ -f '{}' ]; then
    count=$(cat '{}')
  fi
  count=$((count + 1))
  printf '%s' "$count" > '{}'
  if [ "$count" -eq 1 ]; then
    printf '%s\n' '{{"schema_version":"precedent.context.v1","contextBlock":"Precedent:\n- Use repo lesson.","injections":[{{"id":"prec_repo_lesson"}}]}}'
  else
    printf '%s\n' '{{"schema_version":"precedent.context.v1","contextBlock":"","injections":[],"suppressedInjections":[{{"id":"prec_repo_lesson","reason":"already_injected"}}]}}'
  fi
  exit 0
fi
if [ "$1" = "hook" ]; then
  payload=$(cat)
  if printf '%s' "$payload" | grep -q 'repair.before_retry'; then
    printf '%s\n' '{{"schema_version":"precedent.repair.v1","ok":true,"repairBlock":""}}'
    exit 0
  fi
  printf '%s' "$payload" >> '{}'
  printf '\n' >> '{}'
  printf '%s\n' '{{"ok":true}}'
  exit 0
fi
exit 2
"#,
                context_sessions.display(),
                precedent_counter.display(),
                precedent_counter.display(),
                precedent_counter.display(),
                hooks_capture.display(),
                hooks_capture.display()
            ),
        );

        let mut args = base_args();
        args.prompt = Some("ship the feature".to_string());
        args.cd = dir.clone();
        args.interval_seconds = 1;
        args.max_iterations = Some(2);
        args.precedent_state_dir = Some(state_dir);
        args.precedent_bin = precedent_bin;
        args.codex_bin = codex_bin;

        worker_loop(args).unwrap();

        let sessions = fs::read_to_string(context_sessions).unwrap();
        let session_lines: Vec<&str> = sessions.lines().collect();
        assert_eq!(session_lines.len(), 2);
        assert_eq!(session_lines[0], session_lines[1]);
        assert!(!session_lines[0].ends_with("-1"));
        assert!(!session_lines[0].ends_with("-2"));

        let prompts = fs::read_to_string(prompt_capture).unwrap();
        assert_eq!(prompts.matches("Precedent:\n- Use repo lesson.").count(), 1);
        assert_eq!(prompts.matches("ship the feature").count(), 2);

        let hooks = fs::read_to_string(hooks_capture).unwrap();
        assert!(hooks.contains(r#""sessionId":"codex-core-worker-loop-"#));
        assert!(hooks.contains(r#"-1""#));
        assert!(hooks.contains(r#"-2""#));
        assert_eq!(
            hooks
                .matches(r#""attributedPrecedents":["prec_repo_lesson"]"#)
                .count(),
            1
        );
        assert_eq!(hooks.matches(r#""attributedPrecedents":[]"#).count(), 1);

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn worker_loop_fails_open_when_precedent_context_fails() {
        let dir = temp_test_dir("precedent-worker-fail-open");
        let codex_bin = dir.join("fake-codex.sh");
        let precedent_bin = dir.join("broken-precedent.sh");
        let prompt_capture = dir.join("prompt.txt");
        let state_dir = dir.join("state");
        fs::create_dir_all(&state_dir).unwrap();
        write_executable(
            &codex_bin,
            &format!(
                r#"#!/bin/sh
out=""
prompt=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "exec" ]; then
    shift
    prompt="$1"
    shift
    continue
  fi
  if [ "$1" = "--output-last-message" ]; then
    shift
    out="$1"
    shift
    continue
  fi
  shift
done
printf '%s' "$prompt" > '{}'
printf '%s' 'LOOP_DONE from fake codex' > "$out"
"#,
                prompt_capture.display()
            ),
        );
        write_executable(
            &precedent_bin,
            r#"#!/bin/sh
printf '%s\n' 'broken precedent' >&2
exit 2
"#,
        );

        let mut args = base_args();
        args.prompt = Some("ship the feature".to_string());
        args.cd = dir.clone();
        args.once = true;
        args.precedent_state_dir = Some(state_dir);
        args.precedent_bin = precedent_bin;
        args.codex_bin = codex_bin;

        worker_loop(args).unwrap();

        let prompt = fs::read_to_string(prompt_capture).unwrap();
        assert_eq!(prompt, "ship the feature");

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn worker_loop_records_failed_codex_exec_outcome() {
        let dir = temp_test_dir("precedent-worker-codex-failure");
        let codex_bin = dir.join("failing-codex.sh");
        let precedent_bin = dir.join("fake-precedent.sh");
        let hook_capture = dir.join("hook.json");
        let state_dir = dir.join("state");
        fs::create_dir_all(&state_dir).unwrap();
        write_executable(
            &codex_bin,
            r#"#!/bin/sh
printf '%s\n' 'codex exploded' >&2
exit 7
"#,
        );
        write_executable(
            &precedent_bin,
            &format!(
                r#"#!/bin/sh
if [ "$1" = "context" ]; then
  printf '%s\n' '{{"schema_version":"precedent.context.v1","contextBlock":""}}'
  exit 0
fi
if [ "$1" = "hook" ]; then
  cat > '{}'
  printf '%s\n' '{{"ok":true}}'
  exit 0
fi
exit 2
"#,
                hook_capture.display()
            ),
        );

        let mut args = base_args();
        args.prompt = Some("ship the feature".to_string());
        args.cd = dir.clone();
        args.once = true;
        args.precedent_state_dir = Some(state_dir);
        args.precedent_bin = precedent_bin;
        args.codex_bin = codex_bin;

        let error = worker_loop(args).unwrap_err();
        assert!(
            error
                .to_string()
                .contains("codex exec failed on iteration 1")
        );

        let hook = fs::read_to_string(hook_capture).unwrap();
        assert!(hook.contains(r#""hook":"outcome.after_task""#));
        assert!(hook.contains(r#""success":false"#));
        assert!(hook.contains(r#""status":"codex_exec_failed""#));
        assert!(hook.contains("codex exploded"));

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn worker_loop_records_precedent_validation_before_outcome() {
        let dir = temp_test_dir("precedent-worker-validation");
        let codex_bin = dir.join("fake-codex.sh");
        let precedent_bin = dir.join("fake-precedent.sh");
        let hooks_capture = dir.join("hooks.jsonl");
        let state_dir = dir.join("state");
        fs::create_dir_all(&state_dir).unwrap();
        write_executable(
            &codex_bin,
            r#"#!/bin/sh
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output-last-message" ]; then
    shift
    out="$1"
    shift
    continue
  fi
  shift
done
printf '%s' 'LOOP_DONE from fake codex' > "$out"
"#,
        );
        write_executable(
            &precedent_bin,
            &format!(
                r#"#!/bin/sh
if [ "$1" = "context" ]; then
  printf '%s\n' '{{"schema_version":"precedent.context.v1","contextBlock":""}}'
  exit 0
fi
if [ "$1" = "hook" ]; then
  cat >> '{}'
  printf '\n' >> '{}'
  printf '%s\n' '{{"ok":true}}'
  exit 0
fi
exit 2
"#,
                hooks_capture.display(),
                hooks_capture.display()
            ),
        );

        let mut args = base_args();
        args.prompt = Some("ship the feature".to_string());
        args.cd = dir.clone();
        args.once = true;
        args.precedent_state_dir = Some(state_dir);
        args.precedent_validation_command =
            Some("printf validate-out; printf validate-err >&2; exit 7".to_string());
        args.precedent_bin = precedent_bin;
        args.codex_bin = codex_bin;

        worker_loop(args).unwrap();

        let hooks = fs::read_to_string(hooks_capture).unwrap();
        let lines: Vec<&str> = hooks.lines().collect();
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains(r#""hook":"validation.after_run""#));
        assert!(
            lines[0]
                .contains(r#""command":"printf validate-out; printf validate-err >&2; exit 7""#)
        );
        assert!(lines[0].contains(r#""exitCode":7"#));
        assert!(lines[0].contains(r#""stdout":"validate-out""#));
        assert!(lines[0].contains(r#""stderr":"validate-err""#));
        assert!(lines[1].contains(r#""hook":"outcome.after_task""#));
        assert!(lines[1].contains(r#""success":true"#));

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn worker_loop_records_precedent_diff_after_changed_codex_exec() {
        let dir = temp_test_dir("precedent-worker-diff-changed");
        let codex_bin = dir.join("fake-codex.sh");
        let precedent_bin = dir.join("fake-precedent.sh");
        let hooks_capture = dir.join("hooks.jsonl");
        let state_dir = dir.join("state");
        let src_dir = dir.join("src");
        fs::create_dir_all(&src_dir).unwrap();
        fs::write(src_dir.join("lib.rs"), "pub fn existing() {}\n").unwrap();
        write_executable(
            &codex_bin,
            r#"#!/bin/sh
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output-last-message" ]; then
    shift
    out="$1"
    shift
    continue
  fi
  shift
done
printf '%s' 'pub fn changed() {}\n' >> src/lib.rs
printf '%s' 'LOOP_DONE from fake codex' > "$out"
"#,
        );
        write_executable(
            &precedent_bin,
            &format!(
                r#"#!/bin/sh
if [ "$1" = "context" ]; then
  printf '%s\n' '{{"schema_version":"precedent.context.v1","contextBlock":"Precedent:\n- Keep webhook edits scoped.","injections":[{{"id":"prec_repo_lesson"}}]}}'
  exit 0
fi
if [ "$1" = "hook" ]; then
  cat >> '{}'
  printf '\n' >> '{}'
  printf '%s\n' '{{"ok":true}}'
  exit 0
fi
exit 2
"#,
                hooks_capture.display(),
                hooks_capture.display()
            ),
        );
        init_git_repo(&dir);
        fs::create_dir_all(&state_dir).unwrap();

        let mut args = base_args();
        args.prompt = Some("ship the feature".to_string());
        args.cd = dir.clone();
        args.once = true;
        args.precedent_state_dir = Some(state_dir);
        args.precedent_bin = precedent_bin;
        args.codex_bin = codex_bin;

        worker_loop(args).unwrap();

        let hooks = fs::read_to_string(hooks_capture).unwrap();
        let lines: Vec<&str> = hooks.lines().collect();
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains(r#""hook":"diff.after_edit""#));
        assert!(lines[0].contains(r#""changedFiles":["src/lib.rs"]"#));
        assert!(lines[0].contains(r#""linesAdded":1"#));
        assert!(lines[0].contains(r#""linesDeleted":0"#));
        assert!(lines[0].contains(r#""attributedPrecedents":["prec_repo_lesson"]"#));
        assert!(lines[1].contains(r#""hook":"outcome.after_task""#));

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn worker_loop_skips_precedent_diff_when_codex_exec_leaves_git_diff_unchanged() {
        let dir = temp_test_dir("precedent-worker-diff-unchanged");
        let codex_bin = dir.join("fake-codex.sh");
        let precedent_bin = dir.join("fake-precedent.sh");
        let hooks_capture = dir.join("hooks.jsonl");
        let state_dir = dir.join("state");
        fs::write(dir.join("tracked.txt"), "baseline\n").unwrap();
        write_executable(
            &codex_bin,
            r#"#!/bin/sh
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output-last-message" ]; then
    shift
    out="$1"
    shift
    continue
  fi
  shift
done
printf '%s' 'LOOP_DONE from fake codex' > "$out"
"#,
        );
        write_executable(
            &precedent_bin,
            &format!(
                r#"#!/bin/sh
if [ "$1" = "context" ]; then
  printf '%s\n' '{{"schema_version":"precedent.context.v1","contextBlock":"","injections":[]}}'
  exit 0
fi
if [ "$1" = "hook" ]; then
  cat >> '{}'
  printf '\n' >> '{}'
  printf '%s\n' '{{"ok":true}}'
  exit 0
fi
exit 2
"#,
                hooks_capture.display(),
                hooks_capture.display()
            ),
        );
        init_git_repo(&dir);
        fs::create_dir_all(&state_dir).unwrap();

        let mut args = base_args();
        args.prompt = Some("ship the feature".to_string());
        args.cd = dir.clone();
        args.once = true;
        args.precedent_state_dir = Some(state_dir);
        args.precedent_bin = precedent_bin;
        args.codex_bin = codex_bin;

        worker_loop(args).unwrap();

        let hooks = fs::read_to_string(hooks_capture).unwrap();
        let lines: Vec<&str> = hooks.lines().collect();
        assert_eq!(lines.len(), 1);
        assert!(lines[0].contains(r#""hook":"outcome.after_task""#));
        assert!(!hooks.contains(r#""hook":"diff.after_edit""#));

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn worker_loop_skips_precedent_diff_outside_git_repo() {
        let dir = temp_test_dir("precedent-worker-diff-nongit");
        let codex_bin = dir.join("fake-codex.sh");
        let precedent_bin = dir.join("fake-precedent.sh");
        let hooks_capture = dir.join("hooks.jsonl");
        let state_dir = dir.join("state");
        fs::create_dir_all(&state_dir).unwrap();
        write_executable(
            &codex_bin,
            r#"#!/bin/sh
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--output-last-message" ]; then
    shift
    out="$1"
    shift
    continue
  fi
  shift
done
printf '%s' 'changed\n' > edited.txt
printf '%s' 'LOOP_DONE from fake codex' > "$out"
"#,
        );
        write_executable(
            &precedent_bin,
            &format!(
                r#"#!/bin/sh
if [ "$1" = "context" ]; then
  printf '%s\n' '{{"schema_version":"precedent.context.v1","contextBlock":"","injections":[]}}'
  exit 0
fi
if [ "$1" = "hook" ]; then
  cat >> '{}'
  printf '\n' >> '{}'
  printf '%s\n' '{{"ok":true}}'
  exit 0
fi
exit 2
"#,
                hooks_capture.display(),
                hooks_capture.display()
            ),
        );

        let mut args = base_args();
        args.prompt = Some("ship the feature".to_string());
        args.cd = dir.clone();
        args.once = true;
        args.precedent_state_dir = Some(state_dir);
        args.precedent_bin = precedent_bin;
        args.codex_bin = codex_bin;

        worker_loop(args).unwrap();

        let hooks = fs::read_to_string(hooks_capture).unwrap();
        let lines: Vec<&str> = hooks.lines().collect();
        assert_eq!(lines.len(), 1);
        assert!(lines[0].contains(r#""hook":"outcome.after_task""#));
        assert!(!hooks.contains(r#""hook":"diff.after_edit""#));

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn worker_loop_prepends_repair_block_once_on_next_retry() {
        let dir = temp_test_dir("precedent-worker-repair-retry");
        let codex_bin = dir.join("fake-codex.sh");
        let precedent_bin = dir.join("fake-precedent.sh");
        let prompt_capture = dir.join("prompts.txt");
        let repair_capture = dir.join("repair.json");
        let receipt_capture = dir.join("receipt.json");
        let codex_counter = dir.join("codex-count.txt");
        let state_dir = dir.join("state");
        fs::create_dir_all(&state_dir).unwrap();
        write_executable(
            &codex_bin,
            &format!(
                r#"#!/bin/sh
out=""
prompt=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "exec" ]; then
    shift
    prompt="$1"
    shift
    continue
  fi
  if [ "$1" = "--output-last-message" ]; then
    shift
    out="$1"
    shift
    continue
  fi
  shift
done
printf '%s\n---prompt---\n' "$prompt" >> '{}'
count=0
if [ -f '{}' ]; then
  count=$(cat '{}')
fi
count=$((count + 1))
printf '%s' "$count" > '{}'
if [ "$count" -eq 1 ]; then
  printf '%s' 'keep going' > "$out"
else
  printf '%s' 'LOOP_DONE from fake codex' > "$out"
fi
"#,
                prompt_capture.display(),
                codex_counter.display(),
                codex_counter.display(),
                codex_counter.display()
            ),
        );
        write_executable(
            &precedent_bin,
            &format!(
                r#"#!/bin/sh
if [ "$1" = "context" ]; then
  printf '%s\n' '{{"schema_version":"precedent.context.v1","contextBlock":"Precedent:\n- Normal context.","injections":[{{"id":"prec_repo_lesson"}}]}}'
  exit 0
fi
if [ "$1" = "hook" ]; then
  payload=$(cat)
  if printf '%s' "$payload" | grep -q 'repair.before_retry'; then
    printf '%s' "$payload" > '{}'
    printf '%s\n' '{{"schema_version":"precedent.repair.v1","ok":true,"repairId":"repair_test","repairBlock":"Precedent repair:\n- Fix bad path."}}'
    exit 0
  fi
  if printf '%s' "$payload" | grep -q 'repair.after_retry'; then
    printf '%s' "$payload" > '{}'
    printf '%s\n' '{{"schema_version":"precedent.repair_receipt.v1","ok":true,"repairReceipt":{{"id":"repair_test","cleared":true}}}}'
    exit 0
  fi
  printf '%s\n' '{{"ok":true}}'
  exit 0
fi
exit 2
"#,
                repair_capture.display(),
                receipt_capture.display()
            ),
        );

        let mut args = base_args();
        args.prompt = Some("ship the feature".to_string());
        args.cd = dir.clone();
        args.interval_seconds = 1;
        args.max_iterations = Some(2);
        args.precedent_state_dir = Some(state_dir);
        args.precedent_bin = precedent_bin;
        args.codex_bin = codex_bin;

        worker_loop(args).unwrap();

        let prompts_text = fs::read_to_string(prompt_capture).unwrap();
        let prompts: Vec<&str> = prompts_text
            .split("\n---prompt---\n")
            .filter(|prompt| !prompt.trim().is_empty())
            .collect();
        assert_eq!(prompts.len(), 2);
        assert!(!prompts[0].contains("Precedent repair:"));
        assert!(prompts[1].starts_with("Precedent repair:\n- Fix bad path."));
        assert_eq!(prompts_text.matches("Precedent repair:").count(), 1);
        assert!(prompts[1].contains("Precedent:\n- Normal context."));
        assert!(
            prompts[1].find("Precedent repair:") < prompts[1].find("Precedent:\n- Normal context.")
        );

        let repair_payload = fs::read_to_string(repair_capture).unwrap();
        assert!(repair_payload.contains(r#""sessionId":"codex-core-worker-loop-"#));
        assert!(repair_payload.contains(r#"-1""#));
        assert!(repair_payload.contains(r#""nextSessionId":"codex-core-worker-loop-"#));
        assert!(repair_payload.contains(r#"-2""#));
        let receipt_payload = fs::read_to_string(receipt_capture).unwrap();
        assert!(receipt_payload.contains(r#""hook":"repair.after_retry""#));
        assert!(receipt_payload.contains(r#""repairId":"repair_test""#));
        assert!(receipt_payload.contains(r#""repairSessionId":"codex-core-worker-loop-"#));

        let _ = fs::remove_dir_all(dir);
    }

    #[test]
    fn worker_loop_fails_open_when_repair_before_retry_fails() {
        let dir = temp_test_dir("precedent-worker-repair-fail-open");
        let codex_bin = dir.join("fake-codex.sh");
        let precedent_bin = dir.join("fake-precedent.sh");
        let prompt_capture = dir.join("prompts.txt");
        let codex_counter = dir.join("codex-count.txt");
        let state_dir = dir.join("state");
        fs::create_dir_all(&state_dir).unwrap();
        write_executable(
            &codex_bin,
            &format!(
                r#"#!/bin/sh
out=""
prompt=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "exec" ]; then
    shift
    prompt="$1"
    shift
    continue
  fi
  if [ "$1" = "--output-last-message" ]; then
    shift
    out="$1"
    shift
    continue
  fi
  shift
done
printf '%s\n---prompt---\n' "$prompt" >> '{}'
count=0
if [ -f '{}' ]; then
  count=$(cat '{}')
fi
count=$((count + 1))
printf '%s' "$count" > '{}'
if [ "$count" -eq 1 ]; then
  printf '%s' 'keep going' > "$out"
else
  printf '%s' 'LOOP_DONE from fake codex' > "$out"
fi
"#,
                prompt_capture.display(),
                codex_counter.display(),
                codex_counter.display(),
                codex_counter.display()
            ),
        );
        write_executable(
            &precedent_bin,
            r#"#!/bin/sh
if [ "$1" = "context" ]; then
  printf '%s\n' '{"schema_version":"precedent.context.v1","contextBlock":"Precedent:\n- Normal context.","injections":[]}'
  exit 0
fi
if [ "$1" = "hook" ]; then
  payload=$(cat)
  if printf '%s' "$payload" | grep -q 'repair.before_retry'; then
    printf '%s\n' 'not-json'
    exit 0
  fi
  printf '%s\n' '{"ok":true}'
  exit 0
fi
exit 2
"#,
        );

        let mut args = base_args();
        args.prompt = Some("ship the feature".to_string());
        args.cd = dir.clone();
        args.interval_seconds = 1;
        args.max_iterations = Some(2);
        args.precedent_state_dir = Some(state_dir);
        args.precedent_bin = precedent_bin;
        args.codex_bin = codex_bin;

        worker_loop(args).unwrap();

        let prompts_text = fs::read_to_string(prompt_capture).unwrap();
        let prompts: Vec<&str> = prompts_text
            .split("\n---prompt---\n")
            .filter(|prompt| !prompt.trim().is_empty())
            .collect();
        assert_eq!(prompts.len(), 2);
        assert!(!prompts[1].contains("Precedent repair:"));
        assert!(prompts[1].starts_with("Precedent:\n- Normal context."));

        let _ = fs::remove_dir_all(dir);
    }

    fn temp_test_dir(prefix: &str) -> PathBuf {
        let path = env::temp_dir().join(format!(
            "{}-{}",
            prefix,
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        fs::create_dir_all(&path).unwrap();
        path
    }

    fn init_git_repo(path: &PathBuf) {
        run_git(path, &["init"]);
        run_git(path, &["add", "."]);
        run_git(
            path,
            &[
                "-c",
                "user.name=Codex Test",
                "-c",
                "user.email=codex-test@example.com",
                "commit",
                "-m",
                "initial",
            ],
        );
    }

    fn run_git(path: &PathBuf, args: &[&str]) {
        let output = Command::new("git")
            .current_dir(path)
            .args(args)
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "git {} failed: {}",
            args.join(" "),
            String::from_utf8_lossy(&output.stderr)
        );
    }

    fn write_executable(path: &PathBuf, content: &str) {
        fs::write(path, content).unwrap();
        let mut permissions = fs::metadata(path).unwrap().permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(path, permissions).unwrap();
    }
}
