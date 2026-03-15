use crate::cli::{Cli, Command as CliCommand, PromptArgs, ResumeArgs, RunArgs, SharedExecArgs};
use anyhow::{Context, Result, bail};
use clap::Parser;
use serde::Serialize;
use serde_json::Value;
use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

enum PromptValue {
    Direct(String),
    Stdin(String),
}

struct OutputPath {
    path: PathBuf,
    owned: bool,
}

#[derive(Default, Debug)]
struct ParsedEventSummary {
    thread_id: Option<String>,
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
    }
}

fn execute_run(args: RunArgs) -> Result<()> {
    let prompt = resolve_prompt(&args.prompt)?;
    let output_last_message = resolve_output_path(args.shared.output_last_message.clone())?;
    let mut codex_args = build_common_args(&args.shared, &output_last_message.path);

    if let Some(ref prompt_value) = prompt {
        append_prompt_argument(&mut codex_args, &prompt_value);
    }

    run_codex_and_finalize(
        codex_args,
        prompt,
        &output_last_message,
        args.shared.emit_events,
        args.shared.result_json.as_deref(),
    )
}

fn execute_resume(args: ResumeArgs) -> Result<()> {
    validate_resume_args(&args)?;

    let prompt = resolve_prompt(&args.prompt)?;
    let output_last_message = resolve_output_path(args.shared.output_last_message.clone())?;
    let mut codex_args = vec!["exec".to_string(), "resume".to_string()];

    if args.last {
        codex_args.push("--last".to_string());
    }
    if let Some(thread_id) = &args.thread_id {
        codex_args.push(thread_id.clone());
    }

    codex_args.extend(
        build_common_args(&args.shared, &output_last_message.path)
            .into_iter()
            .skip(1),
    );

    if let Some(ref prompt_value) = prompt {
        append_prompt_argument(&mut codex_args, &prompt_value);
    }

    run_codex_and_finalize(
        codex_args,
        prompt,
        &output_last_message,
        args.shared.emit_events,
        args.shared.result_json.as_deref(),
    )
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

fn build_common_args(shared: &SharedExecArgs, output_last_message: &Path) -> Vec<String> {
    let mut args = vec!["exec".to_string(), "--json".to_string()];

    if let Some(cd) = &shared.cd {
        args.push("--cd".to_string());
        args.push(cd.display().to_string());
    }

    if let Some(model) = &shared.model {
        args.push("--model".to_string());
        args.push(model.clone());
    }

    if let Some(sandbox) = shared.sandbox {
        args.push("--sandbox".to_string());
        args.push(sandbox.as_cli_flag().to_string());
    }

    if let Some(approval) = shared.approval {
        args.push("--ask-for-approval".to_string());
        args.push(approval.as_cli_flag().to_string());
    }

    if shared.full_auto {
        args.push("--full-auto".to_string());
    }
    if shared.dangerously_bypass_approvals_and_sandbox {
        args.push("--dangerously-bypass-approvals-and-sandbox".to_string());
    }
    if shared.skip_git_repo_check {
        args.push("--skip-git-repo-check".to_string());
    }
    if shared.ephemeral {
        args.push("--ephemeral".to_string());
    }

    if let Some(schema) = &shared.output_schema {
        args.push("--output-schema".to_string());
        args.push(schema.display().to_string());
    }

    args.push("--output-last-message".to_string());
    args.push(output_last_message.display().to_string());

    if let Some(color) = shared.color {
        args.push("--color".to_string());
        args.push(color.as_cli_flag().to_string());
    }

    args.extend(shared.extra_args.clone());
    args
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
    emit_events: bool,
    result_json: Option<&Path>,
) -> Result<()> {
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

    let output = child
        .wait_with_output()
        .context("failed waiting for codex exec process")?;

    let stdout = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr = String::from_utf8_lossy(&output.stderr).to_string();
    let summary = parse_event_summary(&stdout, emit_events);
    let final_message = read_final_message(&output_last_message.path);

    if let Some(path) = result_json {
        let status = if output.status.success() {
            "completed".to_string()
        } else {
            "failed".to_string()
        };
        write_result_json(
            path,
            &CommandResult {
                status,
                exit_code: output.status.code().unwrap_or(1),
                thread_id: summary.thread_id.clone(),
                final_message: final_message.clone(),
                stderr: stderr.clone(),
            },
        )?;
    }

    cleanup_output_path(output_last_message)?;

    if output.status.success() {
        print!("{final_message}");
        return Ok(());
    }

    if !stderr.trim().is_empty() {
        eprintln!("{stderr}");
    }
    bail!(
        "codex exec failed with exit code {}",
        output.status.code().unwrap_or(1)
    )
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

#[cfg(test)]
mod tests {
    use super::parse_event_summary;

    #[test]
    fn parse_event_summary_extracts_thread_id() {
        let stdout = r#"{"type":"thread.started","thread_id":"abc"}
{"type":"turn.started"}
"#;

        let parsed = parse_event_summary(stdout, false);
        assert_eq!(parsed.thread_id.as_deref(), Some("abc"));
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
