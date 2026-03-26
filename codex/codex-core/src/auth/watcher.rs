use crate::auth::manager::ProfileManager;
use crate::auth::models::{FileSnapshot, WatcherStatus};
use crate::auth::process::{is_auth_watcher_process, is_process_running};
use crate::auth::util::{
    create_directory_if_needed, set_file_permissions, write_secure_atomically,
};
use anyhow::{Context, Result, bail};
use std::fs::{self, OpenOptions};
use std::os::unix::fs::MetadataExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, UNIX_EPOCH};

pub struct AuthSyncWatcher {
    manager: ProfileManager,
    auth_file_path: PathBuf,
    state_directory: PathBuf,
    pid_file_path: PathBuf,
    log_file_path: PathBuf,
}

impl AuthSyncWatcher {
    pub fn new(home_directory: PathBuf) -> Self {
        let manager = ProfileManager::new(home_directory);
        let auth_file_path = manager.paths.codex_auth_file.clone();
        let state_directory = manager.paths.manager_directory.clone();
        let pid_file_path = state_directory.join("watch.pid");
        let log_file_path = state_directory.join("watch.log");

        Self {
            manager,
            auth_file_path,
            state_directory,
            pid_file_path,
            log_file_path,
        }
    }

    pub fn status(&self) -> WatcherStatus {
        let Some(pid) = self.read_pid() else {
            return WatcherStatus::Stopped;
        };

        if is_process_running(pid) && self.is_expected_process(pid) {
            WatcherStatus::Running(pid)
        } else {
            self.clear_pid_file_if_present();
            WatcherStatus::Stopped
        }
    }

    pub fn start_daemon(&self, executable_path: &Path, home_directory: &Path) -> Result<i32> {
        if let WatcherStatus::Running(pid) = self.status() {
            return Ok(pid);
        }

        self.ensure_state_directory()?;

        let log = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.log_file_path)
            .with_context(|| format!("failed to open {}", self.log_file_path.display()))?;
        set_file_permissions(&self.log_file_path, 0o600)?;

        let mut cmd = Command::new(executable_path);
        cmd.arg("auth")
            .arg("--home")
            .arg(home_directory)
            .arg("watch")
            .arg("run")
            .stdin(Stdio::null())
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log));

        let child = cmd.spawn().with_context(|| {
            format!(
                "Failed to start watcher: could not spawn {}",
                executable_path.display()
            )
        })?;

        let pid = child.id() as i32;
        write_secure_atomically(pid.to_string().as_bytes(), &self.pid_file_path)?;
        Ok(pid)
    }

    pub fn stop_daemon(&self) -> Result<()> {
        let Some(pid) = self.read_pid() else {
            return Ok(());
        };

        if !is_process_running(pid) || !self.is_expected_process(pid) {
            self.clear_pid_file_if_present();
            return Ok(());
        }

        let rc = unsafe { libc::kill(pid, libc::SIGTERM) };
        if rc != 0 {
            self.clear_pid_file_if_present();
            bail!("Failed to stop watcher: could not signal process {}", pid);
        }

        self.clear_pid_file_if_present();
        Ok(())
    }

    pub fn run_loop(&self) -> Result<()> {
        let mut last_snapshot = self.snapshot();

        loop {
            let new_snapshot = self.snapshot();
            if new_snapshot != last_snapshot {
                last_snapshot = new_snapshot;
                let _ = self.manager.sync_active_profile_with_current_auth();
            }
            thread::sleep(Duration::from_secs(2));
        }
    }

    fn snapshot(&self) -> Option<FileSnapshot> {
        let metadata = fs::metadata(&self.auth_file_path).ok()?;
        let modified = metadata.modified().ok()?;
        let since_epoch = modified.duration_since(UNIX_EPOCH).ok()?;

        Some(FileSnapshot {
            modification_secs: since_epoch.as_secs() as i64,
            modification_nanos: since_epoch.subsec_nanos() as i64,
            size: metadata.len() as i64,
            inode: metadata.ino() as i64,
        })
    }

    fn read_pid(&self) -> Option<i32> {
        let raw = fs::read_to_string(&self.pid_file_path).ok()?;
        let value = raw.trim();
        if value.is_empty() {
            return None;
        }
        value.parse::<i32>().ok()
    }

    fn clear_pid_file_if_present(&self) {
        let _ = fs::remove_file(&self.pid_file_path);
    }

    fn ensure_state_directory(&self) -> Result<()> {
        create_directory_if_needed(&self.state_directory, 0o700)
    }

    fn is_expected_process(&self, pid: i32) -> bool {
        let Some(home_directory) = self.manager.paths.codex_directory.parent() else {
            return false;
        };
        is_auth_watcher_process(pid, home_directory)
    }
}
