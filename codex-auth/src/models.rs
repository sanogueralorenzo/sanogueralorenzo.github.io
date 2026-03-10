use serde_json::Value;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct AuthPaths {
    pub codex_directory: PathBuf,
    pub codex_auth_file: PathBuf,
    pub codex_auth_lock_file: PathBuf,
    pub manager_directory: PathBuf,
    pub profiles_directory: PathBuf,
    pub active_account_id_file: PathBuf,
    pub legacy_profiles_directory: PathBuf,
}

impl AuthPaths {
    pub fn new(home_directory: PathBuf) -> Self {
        let codex_directory = home_directory.join(".codex");
        let manager_directory = codex_directory.join("auth");

        Self {
            codex_directory: codex_directory.clone(),
            codex_auth_file: codex_directory.join("auth.json"),
            codex_auth_lock_file: codex_directory.join("auth.json.lock"),
            manager_directory: manager_directory.clone(),
            profiles_directory: manager_directory.join("profiles"),
            active_account_id_file: manager_directory.join("active-account-id"),
            legacy_profiles_directory: home_directory.join(".codex-auth").join("profiles"),
        }
    }
}

#[derive(Debug, Clone)]
pub struct ValidatedAuthFile {
    pub raw_data: Vec<u8>,
    pub document_json: Value,
    pub auth_mode: String,
    pub account_id: String,
}

#[derive(Debug, Default)]
pub struct SessionInvalidationResult {
    pub terminated_app_pids: Vec<i32>,
    pub terminated_cli_pids: Vec<i32>,
    pub failed_pids: Vec<i32>,
}

impl SessionInvalidationResult {
    pub fn had_targets(&self) -> bool {
        !self.terminated_app_pids.is_empty()
            || !self.terminated_cli_pids.is_empty()
            || !self.failed_pids.is_empty()
    }

    pub fn merge(&mut self, mut other: SessionInvalidationResult) {
        self.terminated_app_pids
            .append(&mut other.terminated_app_pids);
        self.terminated_cli_pids
            .append(&mut other.terminated_cli_pids);
        self.failed_pids.append(&mut other.failed_pids);
    }
}

#[derive(Debug)]
pub enum CodexAppRelaunchStatus {
    NotAttempted,
    Relaunched,
    Failed(String),
}

#[derive(Debug)]
pub struct SwitchResult {
    pub destination: PathBuf,
    pub source_description: String,
    pub invalidation: SessionInvalidationResult,
    pub codex_app_relaunch_status: CodexAppRelaunchStatus,
}

#[derive(Debug, Clone)]
pub enum ProfileSource {
    Current,
    Path(PathBuf),
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub struct FileSnapshot {
    pub modification_secs: i64,
    pub modification_nanos: i64,
    pub size: i64,
    pub inode: i64,
}

#[derive(Debug, Clone, Eq, PartialEq)]
pub enum WatcherStatus {
    Stopped,
    Running(i32),
}

#[derive(Copy, Clone, Debug, Eq, PartialEq)]
pub enum SessionKind {
    App,
    Cli,
}
