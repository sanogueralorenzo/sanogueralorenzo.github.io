use crate::cli::{
    Cli, ColorMode, Command as CliCommand, ConfigFlagArgs, PromptArgs, ResumeArgs, ReviewArgs,
    RunArgs, WrapperOutputArgs,
};
use anyhow::{Context, Result, bail};
use clap::Parser;
use serde::Serialize;
use serde_json::Value;
use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, ExitStatus, Stdio};
use std::thread;
use std::time::{SystemTime, UNIX_EPOCH};

enum PromptValue {
    Direct(String),
    Stdin(String),
}

struct OutputPath {
    path: PathBuf,
    owned: bool,
}

enum StreamKind {
    Stdout,
    Stderr,
}

struct ProcessOutput {
    status: ExitStatus,
    stdout: String,
    stderr: String,
}

#[derive(Default, Debug)]
struct ParsedEventSummary {
    thread_id: Option<String>,
    last_agent_message: Option<String>,
}

#[derive(Serialize)]
struct CommandResult {
    status: String,
    exit_code: i32,
    thread_id: Option<String>,
    final_message: String,
    stderr: String,
}

pub fn run() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        CliCommand::Run(args) => execute_run(args),
        CliCommand::Resume(args) => execute_resume(args),
        CliCommand::Review(args) => execute_review(args),
    }
}

fn execute_run(args: RunArgs) -> Result<()> {
    let prompt = resolve_prompt(&args.prompt)?;
    let output_last_message = resolve_output_path(args.output.output_last_message.clone())?;
    let mut codex_args = vec!["exec".to_string(), "--json".to_string()];

    append_config_flags(&mut codex_args, &args.config);
    append_paths(&mut codex_args, "--image", &args.image);
    append_flag_value(&mut codex_args, "--model", args.model.as_deref());
    if args.oss {
        codex_args.push("--oss".to_string());
    }
    if let Some(local_provider) = args.local_provider {
        codex_args.push("--local-provider".to_string());
        codex_args.push(local_provider.as_cli_flag().to_string());
    }
    if let Some(sandbox) = args.sandbox {
        codex_args.push("--sandbox".to_string());
        codex_args.push(sandbox.as_cli_flag().to_string());
    }
    append_flag_value(&mut codex_args, "--profile", args.profile.as_deref());
    if let Some(approval) = args.approval {
        codex_args.push("--ask-for-approval".to_string());
        codex_args.push(approval.as_cli_flag().to_string());
    }
    append_exec_toggles(
        &mut codex_args,
        args.full_auto,
        args.dangerously_bypass_approvals_and_sandbox,
        args.skip_git_repo_check,
        args.ephemeral,
    );
    append_path(&mut codex_args, "--cd", args.cd.as_ref());
    append_paths(&mut codex_args, "--add-dir", &args.add_dir);
    append_path(
        &mut codex_args,
        "--output-schema",
        args.output_schema.as_ref(),
    );
    append_output_last_message(&mut codex_args, &output_last_message.path);
    if let Some(color) = args.color {
        codex_args.push("--color".to_string());
        codex_args.push(color_mode_to_cli(color).to_string());
    }
    if args.progress_cursor {
        codex_args.push("--progress-cursor".to_string());
    }
    if let Some(ref prompt_value) = prompt {
        append_prompt_argument(&mut codex_args, prompt_value);
    }

    run_codex_and_finalize(codex_args, prompt, &output_last_message, &args.output)
}

fn execute_resume(args: ResumeArgs) -> Result<()> {
    validate_resume_args(&args)?;

    let prompt = resolve_prompt(&args.prompt)?;
    let output_last_message = resolve_output_path(args.output.output_last_message.clone())?;
    let mut codex_args = vec![
        "exec".to_string(),
        "resume".to_string(),
        "--json".to_string(),
    ];

    append_config_flags(&mut codex_args, &args.config);
    if args.last {
        codex_args.push("--last".to_string());
    }
    if args.all {
        codex_args.push("--all".to_string());
    }
    append_paths(&mut codex_args, "--image", &args.image);
    append_flag_value(&mut codex_args, "--model", args.model.as_deref());
    append_exec_toggles(
        &mut codex_args,
        args.full_auto,
        args.dangerously_bypass_approvals_and_sandbox,
        args.skip_git_repo_check,
        args.ephemeral,
    );
    append_output_last_message(&mut codex_args, &output_last_message.path);
    if let Some(thread_id) = args.thread_id.as_deref() {
        codex_args.push(thread_id.to_string());
    }
    if let Some(ref prompt_value) = prompt {
        append_prompt_argument(&mut codex_args, prompt_value);
    }

    run_codex_and_finalize(codex_args, prompt, &output_last_message, &args.output)
}

fn execute_review(args: ReviewArgs) -> Result<()> {
    let prompt = resolve_prompt(&args.prompt)?;
    let output_last_message = resolve_output_path(args.output.output_last_message.clone())?;
    let mut codex_args = vec![
        "exec".to_string(),
        "review".to_string(),
        "--json".to_string(),
    ];

    append_config_flags(&mut codex_args, &args.config);
    if args.uncommitted {
        codex_args.push("--uncommitted".to_string());
    }
    append_flag_value(&mut codex_args, "--base", args.base.as_deref());
    append_flag_value(&mut codex_args, "--commit", args.commit.as_deref());
    append_flag_value(&mut codex_args, "--model", args.model.as_deref());
    append_flag_value(&mut codex_args, "--title", args.title.as_deref());
    append_exec_toggles(
        &mut codex_args,
        args.full_auto,
        args.dangerously_bypass_approvals_and_sandbox,
        args.skip_git_repo_check,
        args.ephemeral,
    );
    append_output_last_message(&mut codex_args, &output_last_message.path);
    if let Some(ref prompt_value) = prompt {
        append_prompt_argument(&mut codex_args, prompt_value);
    }

    run_codex_and_finalize(codex_args, prompt, &output_last_message, &args.output)
}

fn validate_resume_args(args: &ResumeArgs) -> Result<()> {
    if args.thread_id.is_some() && args.last {
        bail!("resume accepts either <thread_id> or --last, not both");
    }
    if args.thread_id.is_none() && !args.last {
        bail!("resume requires either <thread_id> or --last");
    }
    Ok(())
}

fn resolve_prompt(args: &PromptArgs) -> Result<Option<PromptValue>> {
    if let Some(prompt_text) = &args.prompt {
        return Ok(Some(PromptValue::Direct(prompt_text.clone())));
    }

    if let Some(path) = &args.prompt_file {
        let contents = fs::read_to_string(path)
            .with_context(|| format!("failed to read prompt file: {}", path.display()))?;
        return Ok(Some(PromptValue::Direct(contents)));
    }

    if args.prompt_stdin {
        let mut stdin_contents = String::new();
        io::stdin()
            .read_to_string(&mut stdin_contents)
            .context("failed to read prompt from stdin")?;
        return Ok(Some(PromptValue::Stdin(stdin_contents)));
    }

    Ok(None)
}

fn resolve_output_path(explicit_path: Option<PathBuf>) -> Result<OutputPath> {
    if let Some(path) = explicit_path {
        return Ok(OutputPath { path, owned: false });
    }

    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock is before unix epoch")?
        .as_nanos();
    let path = std::env::temp_dir().join(format!(
        "codex-noninteractive-last-message-{}-{}.txt",
        std::process::id(),
        nanos
    ));

    Ok(OutputPath { path, owned: true })
}

fn append_config_flags(args: &mut Vec<String>, config: &ConfigFlagArgs) {
    for value in &config.config {
        args.push("--config".to_string());
        args.push(value.clone());
    }
    for value in &config.enable {
        args.push("--enable".to_string());
        args.push(value.clone());
    }
    for value in &config.disable {
        args.push("--disable".to_string());
        args.push(value.clone());
    }
}

fn append_exec_toggles(
    args: &mut Vec<String>,
    full_auto: bool,
    dangerous: bool,
    skip_git_repo_check: bool,
    ephemeral: bool,
) {
    if full_auto {
        args.push("--full-auto".to_string());
    }
    if dangerous {
        args.push("--dangerously-bypass-approvals-and-sandbox".to_string());
    }
    if skip_git_repo_check {
        args.push("--skip-git-repo-check".to_string());
    }
    if ephemeral {
        args.push("--ephemeral".to_string());
    }
}

fn append_output_last_message(args: &mut Vec<String>, output_last_message: &Path) {
    args.push("--output-last-message".to_string());
    args.push(output_last_message.display().to_string());
}

fn append_flag_value(args: &mut Vec<String>, flag: &str, value: Option<&str>) {
    if let Some(value) = value {
        args.push(flag.to_string());
        args.push(value.to_string());
    }
}

fn append_path(args: &mut Vec<String>, flag: &str, value: Option<&PathBuf>) {
    if let Some(path) = value {
        args.push(flag.to_string());
        args.push(path.display().to_string());
    }
}

fn append_paths(args: &mut Vec<String>, flag: &str, values: &[PathBuf]) {
    for path in values {
        args.push(flag.to_string());
        args.push(path.display().to_string());
    }
}

fn append_prompt_argument(args: &mut Vec<String>, prompt: &PromptValue) {
    match prompt {
        PromptValue::Direct(text) => args.push(text.clone()),
        PromptValue::Stdin(_) => args.push("-".to_string()),
    }
}

fn run_codex_and_finalize(
    codex_args: Vec<String>,
    prompt: Option<PromptValue>,
    output_last_message: &OutputPath,
    output: &WrapperOutputArgs,
) -> Result<()> {
    let process_output = run_codex_process(codex_args, prompt, output.raw_jsonl)?;
    let summary = parse_event_summary(
        &process_output.stdout,
        output.emit_events && !output.raw_jsonl,
    );
    let file_message = read_final_message(&output_last_message.path);
    let final_message = if file_message.trim().is_empty() {
        summary.last_agent_message.clone().unwrap_or_default()
    } else {
        file_message
    };

    if let Some(path) = output.result_json.as_deref() {
        let status = if process_output.status.success() {
            "completed".to_string()
        } else {
            "failed".to_string()
        };
        write_result_json(
            path,
            &CommandResult {
                status,
                exit_code: process_output.status.code().unwrap_or(1),
                thread_id: summary.thread_id.clone(),
                final_message: final_message.clone(),
                stderr: process_output.stderr.clone(),
            },
        )?;
    }

    cleanup_output_path(output_last_message)?;

    if process_output.status.success() {
        if !output.raw_jsonl {
            print!("{final_message}");
        }
        return Ok(());
    }

    bail!(
        "codex exec failed with exit code {}",
        process_output.status.code().unwrap_or(1)
    )
}

fn run_codex_process(
    codex_args: Vec<String>,
    prompt: Option<PromptValue>,
    forward_stdout: bool,
) -> Result<ProcessOutput> {
    let mut command = Command::new("codex");
    command
        .args(&codex_args)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());

    if matches!(prompt, Some(PromptValue::Stdin(_))) {
        command.stdin(Stdio::piped());
    }

    let mut child = command
        .spawn()
        .context("failed to spawn codex (is Codex CLI installed and on PATH?)")?;

    if let Some(PromptValue::Stdin(contents)) = &prompt {
        let Some(mut stdin) = child.stdin.take() else {
            bail!("internal error: stdin pipe missing for prompt");
        };
        stdin
            .write_all(contents.as_bytes())
            .context("failed writing prompt to codex stdin")?;
    }

    let Some(stdout_pipe) = child.stdout.take() else {
        bail!("failed to capture codex stdout");
    };
    let Some(stderr_pipe) = child.stderr.take() else {
        bail!("failed to capture codex stderr");
    };

    let stdout_reader =
        thread::spawn(move || read_stream(stdout_pipe, StreamKind::Stdout, forward_stdout));
    let stderr_reader = thread::spawn(move || read_stream(stderr_pipe, StreamKind::Stderr, true));

    let status = child
        .wait()
        .context("failed waiting for codex exec process")?;

    let stdout_bytes = stdout_reader
        .join()
        .map_err(|_| anyhow::anyhow!("stdout reader thread panicked"))??;
    let stderr_bytes = stderr_reader
        .join()
        .map_err(|_| anyhow::anyhow!("stderr reader thread panicked"))??;

    let stdout = String::from_utf8_lossy(&stdout_bytes).to_string();
    let stderr = String::from_utf8_lossy(&stderr_bytes).to_string();

    Ok(ProcessOutput {
        status,
        stdout,
        stderr,
    })
}

fn read_stream<R: Read>(mut reader: R, kind: StreamKind, forward: bool) -> Result<Vec<u8>> {
    let mut collected = Vec::new();
    let mut chunk = [0_u8; 8 * 1024];
    let mut writer: Option<Box<dyn Write + Send>> = if forward {
        match kind {
            StreamKind::Stdout => Some(Box::new(io::stdout())),
            StreamKind::Stderr => Some(Box::new(io::stderr())),
        }
    } else {
        None
    };

    loop {
        let count = reader
            .read(&mut chunk)
            .context("failed reading codex stream")?;
        if count == 0 {
            break;
        }
        collected.extend_from_slice(&chunk[..count]);

        if let Some(ref mut sink) = writer {
            sink.write_all(&chunk[..count])
                .context("failed forwarding codex stream")?;
            sink.flush().context("failed flushing codex stream")?;
        }
    }

    Ok(collected)
}

fn parse_event_summary(stdout: &str, emit_events: bool) -> ParsedEventSummary {
    let mut summary = ParsedEventSummary::default();

    for line in stdout.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }
        if emit_events {
            eprintln!("{trimmed}");
        }

        let Ok(value) = serde_json::from_str::<Value>(trimmed) else {
            continue;
        };

        if value.get("type").and_then(Value::as_str) == Some("thread.started") {
            if let Some(thread_id) = value.get("thread_id").and_then(Value::as_str) {
                summary.thread_id = Some(thread_id.to_string());
            }
            continue;
        }

        if value.get("type").and_then(Value::as_str) != Some("item.completed") {
            continue;
        }

        let Some(item) = value.get("item") else {
            continue;
        };
        if item.get("type").and_then(Value::as_str) != Some("agent_message") {
            continue;
        }
        if let Some(text) = item.get("text").and_then(Value::as_str) {
            summary.last_agent_message = Some(text.to_string());
        }
    }

    summary
}

fn read_final_message(path: &Path) -> String {
    fs::read_to_string(path).unwrap_or_default()
}

fn write_result_json(path: &Path, result: &CommandResult) -> Result<()> {
    let payload =
        serde_json::to_string_pretty(result).context("failed to serialize result JSON")?;
    fs::write(path, format!("{payload}\n"))
        .with_context(|| format!("failed to write result JSON: {}", path.display()))?;
    Ok(())
}

fn cleanup_output_path(output: &OutputPath) -> Result<()> {
    if output.owned && output.path.exists() {
        fs::remove_file(&output.path).with_context(|| {
            format!(
                "failed to remove temporary output file: {}",
                output.path.display()
            )
        })?;
    }
    Ok(())
}

fn color_mode_to_cli(color: ColorMode) -> &'static str {
    color.as_cli_flag()
}

#[cfg(test)]
mod tests {
    use super::parse_event_summary;

    #[test]
    fn parse_event_summary_extracts_thread_id() {
        let stdout = r#"{"type":"thread.started","thread_id":"abc"}
{"type":"item.completed","item":{"type":"agent_message","text":"hello"}}
"#;

        let parsed = parse_event_summary(stdout, false);
        assert_eq!(parsed.thread_id.as_deref(), Some("abc"));
        assert_eq!(parsed.last_agent_message.as_deref(), Some("hello"));
    }

    #[test]
    fn parse_event_summary_ignores_non_json_lines() {
        let stdout = r#"not-json
{"type":"turn.started"}
"#;

        let parsed = parse_event_summary(stdout, false);
        assert_eq!(parsed.thread_id, None);
    }
}
