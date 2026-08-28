use crate::sessions::shared::models::SessionMeta;
use anyhow::{Context, Result, bail};
use std::fs;
use std::process::Command;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

pub(crate) fn run_codex_exec_resume(target: &SessionMeta, prompt: &str) -> Result<()> {
    let mut command = base_codex_exec_resume_command(target, prompt);

    let output = command
        .output()
        .with_context(|| format!("failed running codex exec resume for target {}", target.id))?;

    if output.status.success() {
        return Ok(());
    }

    let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
    let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let detail = if !stderr.is_empty() {
        stderr
    } else if !stdout.is_empty() {
        stdout
    } else {
        format!("process exited with status {}", output.status)
    };
    bail!("codex exec resume failed while merging sessions: {detail}");
}

pub(crate) fn run_codex_exec_resume_capture_last_message(
    target: &SessionMeta,
    prompt: &str,
) -> Result<String> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0));
    let output_file = std::env::temp_dir().join(format!(
        "codex-core-merge-last-message-{}-{}.txt",
        std::process::id(),
        now.as_nanos()
    ));

    let mut command = base_codex_exec_resume_command(target, prompt);
    command.arg("--output-last-message").arg(&output_file);

    let output = command
        .output()
        .with_context(|| format!("failed running codex exec resume for session {}", target.id))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let detail = if !stderr.is_empty() {
            stderr
        } else if !stdout.is_empty() {
            stdout
        } else {
            format!("process exited with status {}", output.status)
        };
        let _ = fs::remove_file(&output_file);
        bail!("codex exec resume failed while generating merge summary: {detail}");
    }

    let summary = fs::read_to_string(&output_file).with_context(|| {
        format!(
            "failed reading generated merge summary from {}",
            output_file.display()
        )
    })?;
    let _ = fs::remove_file(&output_file);

    let trimmed = summary.trim();
    if trimmed.is_empty() {
        bail!("merge summary generation produced an empty result");
    }

    Ok(trimmed.to_string())
}

fn base_codex_exec_resume_command(target: &SessionMeta, prompt: &str) -> Command {
    let mut command = Command::new("codex");
    command
        .arg("-a")
        .arg("never")
        .arg("-s")
        .arg("workspace-write");

    if let Some(cwd) = target.cwd.as_deref() {
        let cwd_path = std::path::Path::new(cwd);
        if cwd_path.exists() {
            command.arg("-C").arg(cwd);
        }
    }

    command
        .arg("exec")
        .arg("resume")
        .arg("--skip-git-repo-check")
        .arg(&target.id)
        .arg(prompt);

    command
}
