use std::path::Path;
use std::process::Command;

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

#[cfg(test)]
mod tests {
    use super::is_auth_watcher_command;
    use std::path::Path;

    #[test]
    fn auth_watcher_command_is_detected_for_same_home() {
        let command = "/opt/homebrew/bin/codex-core auth --home /Users/mario watch run";
        assert!(is_auth_watcher_command(command, Path::new("/Users/mario")));
    }

    #[test]
    fn auth_watcher_command_is_rejected_for_different_home() {
        let command = "/opt/homebrew/bin/codex-core auth --home /Users/other watch run";
        assert!(!is_auth_watcher_command(command, Path::new("/Users/mario")));
    }
}
