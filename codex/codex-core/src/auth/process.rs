use anyhow::{Context, Result, bail};
use std::path::Path;
use std::process::Command;
use std::thread;
use std::time::Duration;

pub fn terminate_running_codex_app_sessions() -> Result<bool> {
    let targets = collect_codex_app_pids();
    if targets.is_empty() {
        return Ok(false);
    }

    let mut failed_pids = Vec::new();
    for pid in targets {
        if !terminate_process(pid) {
            failed_pids.push(pid);
        }
    }

    if !failed_pids.is_empty() {
        bail!(
            "Failed to terminate running Codex app process(es): {}",
            join_i32(&failed_pids)
        );
    }

    Ok(true)
}

pub fn is_codex_app_running() -> bool {
    !collect_codex_app_pids().is_empty()
}

pub fn relaunch_codex_app() -> Result<()> {
    #[cfg(not(target_os = "macos"))]
    {
        bail!("Relaunching Codex app is only supported on macOS.");
    }

    #[cfg(target_os = "macos")]
    {
        let status = Command::new("/usr/bin/open")
            .args(["-a", "Codex"])
            .status()
            .context("Failed to launch '/usr/bin/open' for Codex app relaunch")?;

        if !status.success() {
            bail!("Failed to relaunch Codex app with '/usr/bin/open -a Codex'.");
        }

        Ok(())
    }
}

fn collect_codex_app_pids() -> Vec<i32> {
    let current_pid = std::process::id() as i32;
    let entries = running_processes();

    let mut targets = Vec::new();
    for (pid, command) in &entries {
        if *pid == current_pid {
            continue;
        }

        if !is_codex_app_command(command) {
            continue;
        }

        targets.push(*pid);
    }

    targets
}

fn running_processes() -> Vec<(i32, String)> {
    let Ok(output) = Command::new("/bin/ps")
        .args(["-axo", "pid=,command="])
        .output()
    else {
        return Vec::new();
    };

    if !output.status.success() {
        return Vec::new();
    }

    let text = String::from_utf8_lossy(&output.stdout);
    let mut result = Vec::new();

    for raw_line in text.lines() {
        let line = raw_line.trim();
        if line.is_empty() {
            continue;
        }

        let mut parts = line.splitn(2, char::is_whitespace);
        let Some(pid_raw) = parts.next() else {
            continue;
        };
        let Some(command_raw) = parts.next() else {
            continue;
        };

        let Ok(pid) = pid_raw.trim().parse::<i32>() else {
            continue;
        };

        let command = command_raw.trim();
        if command.is_empty() {
            continue;
        }

        result.push((pid, command.to_string()));
    }

    result
}

fn is_codex_app_command(command: &str) -> bool {
    command.contains("/Codex.app/Contents/")
}

fn terminate_process(pid: i32) -> bool {
    if !send_signal_allow_missing(pid, libc::SIGTERM) {
        return false;
    }
    if wait_for_exit(pid, Duration::from_millis(500)) {
        return true;
    }

    if !send_signal_allow_missing(pid, libc::SIGKILL) {
        return false;
    }

    wait_for_exit(pid, Duration::from_millis(500))
}

fn send_signal_allow_missing(pid: i32, signal: i32) -> bool {
    let rc = unsafe { libc::kill(pid, signal) };
    if rc == 0 {
        return true;
    }
    last_errno() == libc::ESRCH
}

fn wait_for_exit(pid: i32, timeout: Duration) -> bool {
    let interval = Duration::from_millis(100);
    let mut waited = Duration::from_millis(0);

    while waited < timeout {
        if !is_process_running(pid) {
            return true;
        }
        thread::sleep(interval);
        waited += interval;
    }

    !is_process_running(pid)
}

pub fn is_process_running(pid: i32) -> bool {
    let rc = unsafe { libc::kill(pid, 0) };
    if rc == 0 {
        return true;
    }
    last_errno() == libc::EPERM
}

pub fn is_auth_watcher_process(pid: i32, home_directory: &Path) -> bool {
    let Some(command) = command_for_pid(pid) else {
        return false;
    };
    is_auth_watcher_command(&command, home_directory)
}

fn command_for_pid(pid: i32) -> Option<String> {
    let output = Command::new("/bin/ps")
        .args(["-p", &pid.to_string(), "-o", "command="])
        .output()
        .ok()?;
    if !output.status.success() {
        return None;
    }

    let command = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if command.is_empty() {
        return None;
    }

    Some(command)
}

fn is_auth_watcher_command(command: &str, home_directory: &Path) -> bool {
    let home_directory = home_directory.to_string_lossy();
    command.contains("codex-core")
        && command.contains(" auth")
        && command.contains(" watch")
        && command.contains(" run")
        && command.contains(home_directory.as_ref())
}

fn last_errno() -> i32 {
    #[cfg(target_os = "macos")]
    unsafe {
        *libc::__error()
    }

    #[cfg(not(target_os = "macos"))]
    unsafe {
        *libc::__errno_location()
    }
}

fn join_i32(values: &[i32]) -> String {
    values
        .iter()
        .map(|pid| pid.to_string())
        .collect::<Vec<String>>()
        .join(", ")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codex_app_command_is_detected() {
        let command = "/Applications/Codex.app/Contents/MacOS/Codex";
        assert!(is_codex_app_command(command));
    }

    #[test]
    fn non_codex_app_command_is_ignored() {
        let command = "/opt/homebrew/bin/codex exec \"hello\"";
        assert!(!is_codex_app_command(command));
    }

    #[test]
    fn auth_watcher_command_is_detected_for_same_home() {
        let command = "/opt/homebrew/bin/codex-core auth --home /Users/mario watch run";
        assert!(is_auth_watcher_command(
            command,
            Path::new("/Users/mario")
        ));
    }

    #[test]
    fn auth_watcher_command_is_rejected_for_different_home() {
        let command = "/opt/homebrew/bin/codex-core auth --home /Users/other watch run";
        assert!(!is_auth_watcher_command(
            command,
            Path::new("/Users/mario")
        ));
    }
}
