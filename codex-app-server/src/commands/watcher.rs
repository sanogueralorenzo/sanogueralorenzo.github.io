use crate::adapters::session_store::SessionStore;
use crate::cli::WatchTitleCommand;
use crate::shared::models::SessionMeta;
use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use super::title_generation::generate_session_title;

const WATCH_TITLE_INTERVAL: Duration = Duration::from_secs(10);
const WATCH_TITLE_BATCH_LIMIT: usize = 100;
const WATCH_TITLE_PID_FILE: &str = "codex-app-server-watch-thread-titles.pid";
const WATCH_TITLE_LOG_FILE: &str = "codex-app-server-watch-thread-titles.log";
const WATCH_TITLE_STATE_FILE: &str = "codex-app-server-watch-thread-titles.state.json";

pub(crate) fn cmd_watch_thread_titles(action: WatchTitleCommand) -> Result<()> {
    match action {
        WatchTitleCommand::Start(args) => {
            let watcher = TitleWatcher::new(args.home)?;
            let executable =
                std::env::current_exe().context("failed to resolve current executable")?;
            let pid = watcher.start_daemon(&executable)?;
            println!("Thread-titles watcher running (PID {pid})");
        }
        WatchTitleCommand::Stop(args) => {
            let watcher = TitleWatcher::new(args.home)?;
            watcher.stop_daemon()?;
            println!("Thread-titles watcher stopped");
        }
        WatchTitleCommand::Status(args) => {
            let watcher = TitleWatcher::new(args.home)?;
            match watcher.status() {
                TitleWatcherStatus::Stopped => println!("Thread-titles watcher stopped"),
                TitleWatcherStatus::Running(pid) => {
                    println!("Thread-titles watcher running (PID {pid})")
                }
            }
        }
        WatchTitleCommand::Run(args) => {
            let watcher = TitleWatcher::new(args.home)?;
            watcher.run_loop(args.once)?;
        }
    }

    Ok(())
}

#[derive(Debug, Clone, Eq, PartialEq)]
enum TitleWatcherStatus {
    Stopped,
    Running(i32),
}

#[derive(Debug, Clone, Default, Serialize, Deserialize)]
struct TitleWatcherState {
    last_updated_at: Option<i64>,
    last_id: Option<String>,
}

#[derive(Debug, Default)]
struct TitleWatcherCycleReport {
    scanned: usize,
    generated: usize,
    skipped_non_empty: usize,
    skipped_not_ready: usize,
    missing: usize,
    errors: usize,
}

struct TitleWatcher {
    codex_home: PathBuf,
    state_directory: PathBuf,
    pid_file_path: PathBuf,
    log_file_path: PathBuf,
    state_file_path: PathBuf,
}

impl TitleWatcher {
    fn new(home: Option<PathBuf>) -> Result<Self> {
        let store = SessionStore::new(home)?;
        let codex_home = store.codex_home().to_path_buf();
        let state_directory = codex_home.join("sessions");
        Ok(Self {
            codex_home,
            pid_file_path: state_directory.join(WATCH_TITLE_PID_FILE),
            log_file_path: state_directory.join(WATCH_TITLE_LOG_FILE),
            state_file_path: state_directory.join(WATCH_TITLE_STATE_FILE),
            state_directory,
        })
    }

    fn status(&self) -> TitleWatcherStatus {
        let Some(pid) = self.read_pid() else {
            return TitleWatcherStatus::Stopped;
        };

        if is_process_running(pid) {
            TitleWatcherStatus::Running(pid)
        } else {
            self.clear_pid_file_if_present();
            TitleWatcherStatus::Stopped
        }
    }

    fn start_daemon(&self, executable_path: &Path) -> Result<i32> {
        if let TitleWatcherStatus::Running(pid) = self.status() {
            return Ok(pid);
        }

        self.ensure_state_directory()?;

        let log = OpenOptions::new()
            .create(true)
            .append(true)
            .open(&self.log_file_path)
            .with_context(|| format!("failed to open {}", self.log_file_path.display()))?;
        set_permissions(&self.log_file_path, 0o600)?;

        let mut command = Command::new(executable_path);
        command
            .arg("sessions")
            .arg("watch")
            .arg("thread-titles")
            .arg("run")
            .arg("--home")
            .arg(&self.codex_home)
            .stdin(Stdio::null())
            .stdout(Stdio::from(log.try_clone()?))
            .stderr(Stdio::from(log));

        let child = command.spawn().with_context(|| {
            format!(
                "failed to start title watcher: could not spawn {}",
                executable_path.display()
            )
        })?;

        let pid = child.id() as i32;
        self.write_pid(pid)?;
        Ok(pid)
    }

    fn stop_daemon(&self) -> Result<()> {
        let Some(pid) = self.read_pid() else {
            return Ok(());
        };

        let rc = unsafe { libc::kill(pid, libc::SIGTERM) };
        if rc != 0 {
            self.clear_pid_file_if_present();
            bail!(
                "failed to stop title watcher: could not signal process {}",
                pid
            );
        }

        self.clear_pid_file_if_present();
        Ok(())
    }

    fn run_loop(&self, once: bool) -> Result<()> {
        self.ensure_state_directory()?;

        let store = SessionStore::new(Some(self.codex_home.clone()))?;
        let mut state = self.load_state()?;

        loop {
            let report = self.process_cycle(&store, &mut state)?;
            self.save_state(&state)?;
            eprintln!(
                "[codex-app-server:watch-thread-titles] scanned={} generated={} skipped_non_empty={} skipped_not_ready={} missing={} errors={} watermark_updated_at={} watermark_id={}",
                report.scanned,
                report.generated,
                report.skipped_non_empty,
                report.skipped_not_ready,
                report.missing,
                report.errors,
                state
                    .last_updated_at
                    .map(|value| value.to_string())
                    .unwrap_or_else(|| "none".to_string()),
                state.last_id.clone().unwrap_or_else(|| "none".to_string())
            );

            if once {
                break;
            }

            thread::sleep(WATCH_TITLE_INTERVAL);
        }

        Ok(())
    }

    fn process_cycle(
        &self,
        store: &SessionStore,
        state: &mut TitleWatcherState,
    ) -> Result<TitleWatcherCycleReport> {
        let mut report = TitleWatcherCycleReport::default();
        let candidates = store.list_untitled_thread_candidates(
            state.last_updated_at,
            state.last_id.as_deref(),
            WATCH_TITLE_BATCH_LIMIT,
        )?;
        report.scanned = candidates.len();
        if candidates.is_empty() {
            return Ok(report);
        }

        let sessions = store.collect_sessions()?;
        let sessions_by_id: HashMap<String, SessionMeta> = sessions
            .into_iter()
            .map(|session| (session.id.clone(), session))
            .collect();

        let mut next_state = state.clone();
        let mut state_blocked = false;

        for candidate in candidates {
            let mut advance_state = || {
                if !state_blocked {
                    next_state.last_updated_at = Some(candidate.updated_at);
                    next_state.last_id = Some(candidate.id.clone());
                }
            };

            if store.has_non_empty_thread_title(&candidate.id)? {
                report.skipped_non_empty += 1;
                advance_state();
                continue;
            }

            let Some(session) = sessions_by_id.get(&candidate.id) else {
                report.missing += 1;
                advance_state();
                continue;
            };

            if store
                .read_latest_assistant_message(&session.file_path)?
                .is_none()
            {
                report.skipped_not_ready += 1;
                advance_state();
                continue;
            }

            let Some(first_user_prompt) = store.read_first_user_message(session)? else {
                report.skipped_not_ready += 1;
                advance_state();
                continue;
            };

            let generated_title = match generate_session_title(session, &first_user_prompt) {
                Ok(title) => title,
                Err(error) => {
                    report.errors += 1;
                    state_blocked = true;
                    eprintln!(
                        "[codex-app-server:watch-thread-titles] generate failed id={} error={}",
                        candidate.id, error
                    );
                    continue;
                }
            };

            if store.has_non_empty_thread_title(&candidate.id)? {
                report.skipped_non_empty += 1;
                advance_state();
                continue;
            }

            if let Err(error) = store.set_thread_title(&candidate.id, &generated_title) {
                report.errors += 1;
                state_blocked = true;
                eprintln!(
                    "[codex-app-server:watch-thread-titles] persist failed id={} error={}",
                    candidate.id, error
                );
                continue;
            }

            report.generated += 1;
            advance_state();
        }

        if !state_blocked {
            *state = next_state;
        }

        Ok(report)
    }

    fn load_state(&self) -> Result<TitleWatcherState> {
        if !self.state_file_path.exists() {
            return Ok(TitleWatcherState::default());
        }

        let raw = fs::read_to_string(&self.state_file_path)
            .with_context(|| format!("failed to read {}", self.state_file_path.display()))?;
        let state: TitleWatcherState = serde_json::from_str(&raw)
            .with_context(|| format!("failed to parse {}", self.state_file_path.display()))?;
        Ok(state)
    }

    fn save_state(&self, state: &TitleWatcherState) -> Result<()> {
        let serialized = format!("{}\n", serde_json::to_string_pretty(state)?);
        write_text_file_atomic(&self.state_file_path, &serialized)?;
        set_permissions(&self.state_file_path, 0o600)?;
        Ok(())
    }

    fn read_pid(&self) -> Option<i32> {
        let raw = fs::read_to_string(&self.pid_file_path).ok()?;
        let value = raw.trim();
        if value.is_empty() {
            return None;
        }
        value.parse::<i32>().ok()
    }

    fn write_pid(&self, pid: i32) -> Result<()> {
        let serialized = format!("{pid}\n");
        write_text_file_atomic(&self.pid_file_path, &serialized)?;
        set_permissions(&self.pid_file_path, 0o600)?;
        Ok(())
    }

    fn clear_pid_file_if_present(&self) {
        let _ = fs::remove_file(&self.pid_file_path);
    }

    fn ensure_state_directory(&self) -> Result<()> {
        fs::create_dir_all(&self.state_directory)
            .with_context(|| format!("failed to create {}", self.state_directory.display()))?;
        set_permissions(&self.state_directory, 0o700)?;
        Ok(())
    }
}

fn set_permissions(path: &Path, mode: u32) -> Result<()> {
    let mut permissions = fs::metadata(path)
        .with_context(|| format!("failed to read metadata for {}", path.display()))?
        .permissions();
    permissions.set_mode(mode);
    fs::set_permissions(path, permissions)
        .with_context(|| format!("failed to set permissions for {}", path.display()))
}

fn is_process_running(pid: i32) -> bool {
    let rc = unsafe { libc::kill(pid, 0) };
    if rc == 0 {
        return true;
    }

    let error = std::io::Error::last_os_error();
    error.raw_os_error() == Some(libc::EPERM)
}

fn write_text_file_atomic(path: &Path, contents: &str) -> Result<()> {
    let Some(parent) = path.parent() else {
        bail!("path has no parent: {}", path.display());
    };
    fs::create_dir_all(parent).with_context(|| format!("failed to create {}", parent.display()))?;

    let file_name = path
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| anyhow::anyhow!("invalid file name for {}", path.display()))?;
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0))
        .as_nanos();
    let tmp_path = parent.join(format!(".{file_name}.tmp-{}-{nonce}", std::process::id()));

    let result = (|| -> Result<()> {
        let mut file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&tmp_path)
            .with_context(|| format!("failed to create {}", tmp_path.display()))?;
        file.write_all(contents.as_bytes())
            .with_context(|| format!("failed to write {}", tmp_path.display()))?;
        file.sync_all()
            .with_context(|| format!("failed to fsync {}", tmp_path.display()))?;
        drop(file);

        fs::rename(&tmp_path, path).with_context(|| {
            format!(
                "failed to rename {} to {}",
                tmp_path.display(),
                path.display()
            )
        })?;

        let dir = OpenOptions::new()
            .read(true)
            .open(parent)
            .with_context(|| format!("failed to open directory {}", parent.display()))?;
        dir.sync_all()
            .with_context(|| format!("failed to fsync directory {}", parent.display()))?;

        Ok(())
    })();

    if result.is_err() {
        let _ = fs::remove_file(&tmp_path);
    }

    result
}
