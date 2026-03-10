use crate::models::{SessionInvalidationResult, SessionKind};
use crate::util::is_executable;
use anyhow::{Context, Result, bail};
use std::collections::{BTreeMap, HashSet};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::Duration;

pub fn invalidate_running_codex_sessions() -> SessionInvalidationResult {
    terminate_targets(collect_codex_targets(None))
}

pub fn terminate_running_codex_app_sessions() -> SessionInvalidationResult {
    terminate_targets(collect_codex_targets(Some(SessionKind::App)))
}

pub fn is_codex_app_running() -> bool {
    !collect_codex_targets(Some(SessionKind::App)).is_empty()
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

fn collect_codex_targets(kind_filter: Option<SessionKind>) -> BTreeMap<i32, SessionKind> {
    let current_pid = std::process::id() as i32;
    let entries = running_processes();
    let official_cli_entrypoints = resolve_official_codex_cli_entrypoints();

    let mut targets: BTreeMap<i32, SessionKind> = BTreeMap::new();
    for (pid, command) in entries {
        if pid == current_pid {
            continue;
        }

        let Some(kind) = classify_process(&command, &official_cli_entrypoints) else {
            continue;
        };

        if let Some(filter_kind) = kind_filter
            && kind != filter_kind
        {
            continue;
        }

        if let Some(existing) = targets.get(&pid) {
            if *existing == SessionKind::App {
                continue;
            }
        }
        targets.insert(pid, kind);
    }

    targets
}

fn terminate_targets(targets: BTreeMap<i32, SessionKind>) -> SessionInvalidationResult {
    let mut terminated_app_pids = Vec::new();
    let mut terminated_cli_pids = Vec::new();
    let mut failed_pids = Vec::new();

    for (pid, kind) in targets {
        if terminate_process(pid) {
            match kind {
                SessionKind::App => terminated_app_pids.push(pid),
                SessionKind::Cli => terminated_cli_pids.push(pid),
            }
        } else {
            failed_pids.push(pid);
        }
    }

    SessionInvalidationResult {
        terminated_app_pids,
        terminated_cli_pids,
        failed_pids,
    }
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

fn classify_process(
    command: &str,
    official_cli_entrypoints: &HashSet<String>,
) -> Option<SessionKind> {
    if is_codex_app_command(command) {
        return Some(SessionKind::App);
    }

    if command.contains("codex-auth") {
        return None;
    }

    for token in command.split_whitespace() {
        let raw = token.trim_matches('"').trim_matches('\'');
        if raw.is_empty() {
            continue;
        }

        if official_cli_entrypoints.contains(raw) {
            return Some(SessionKind::Cli);
        }

        if raw.contains("/node_modules/@openai/codex/")
            || raw.contains("/node_modules/@openai/codex-")
        {
            return Some(SessionKind::Cli);
        }
    }

    if command.to_lowercase().contains("@openai/codex") {
        return Some(SessionKind::Cli);
    }

    None
}

fn is_codex_app_command(command: &str) -> bool {
    command.contains("/Codex.app/Contents/")
}

fn resolve_official_codex_cli_entrypoints() -> HashSet<String> {
    let which_path = if is_executable(Path::new("/usr/bin/which")) {
        PathBuf::from("/usr/bin/which")
    } else {
        PathBuf::from("/bin/which")
    };

    let Ok(output) = Command::new(which_path).args(["-a", "codex"]).output() else {
        return HashSet::new();
    };

    if !output.status.success() {
        return HashSet::new();
    }

    let text = String::from_utf8_lossy(&output.stdout);
    let mut set = HashSet::new();

    for line in text.lines() {
        let path = line.trim();
        if path.is_empty() {
            continue;
        }

        let resolved = fs::canonicalize(path)
            .map(|p| p.display().to_string())
            .unwrap_or_else(|_| path.to_string());

        if resolved.contains("/@openai/codex/") || path.contains("/@openai/codex/") {
            set.insert(path.to_string());
            set.insert(resolved);
        }
    }

    set
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn classify_process_marks_codex_app_as_app_session() {
        let command = "/Applications/Codex.app/Contents/MacOS/Codex";
        let kind = classify_process(command, &HashSet::new());
        assert_eq!(kind, Some(SessionKind::App));
    }

    #[test]
    fn classify_process_ignores_codex_auth_process() {
        let command = "/usr/local/bin/codex-auth use work";
        let kind = classify_process(command, &HashSet::new());
        assert_eq!(kind, None);
    }
}
