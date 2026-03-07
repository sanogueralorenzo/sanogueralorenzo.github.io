use anyhow::{Context, Result, bail};
use clap::{Args, Parser, Subcommand};
use fs2::FileExt;
use serde_json::Value;
use std::collections::{BTreeMap, HashSet};
use std::ffi::OsStr;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::os::unix::fs::{MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[derive(Parser, Debug)]
#[command(name = "codex-auth")]
#[command(about = "Manage Codex auth profiles")]
struct Cli {
    #[arg(long, global = true, value_name = "dir")]
    home: Option<PathBuf>,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand, Debug)]
enum Commands {
    /// Save a profile from current auth.json or explicit --path
    #[command(alias = "add")]
    Save(SaveArgs),

    /// Apply a saved profile or explicit --path to auth.json
    Use(UseArgs),

    /// List saved profiles
    List(PlainArgs),

    /// Print current profile and auth metadata
    Current(PlainArgs),

    /// Delete a saved profile
    #[command(alias = "rm", alias = "delete")]
    Remove(RemoveArgs),

    /// Manage auth sync watcher (start|stop|status|run)
    Watch {
        #[command(subcommand)]
        action: WatchCommand,
    },
}

#[derive(Args, Debug)]
struct SaveArgs {
    profile: String,

    #[arg(long, value_name = "auth.json", conflicts_with = "from_current")]
    path: Option<PathBuf>,

    #[arg(long)]
    from_current: bool,
}

#[derive(Args, Debug)]
struct UseArgs {
    profile: Option<String>,

    #[arg(long, value_name = "auth.json")]
    path: Option<PathBuf>,
}

#[derive(Args, Debug)]
struct PlainArgs {
    #[arg(long)]
    plain: bool,
}

#[derive(Args, Debug)]
struct RemoveArgs {
    profile: String,
}

#[derive(Subcommand, Debug)]
enum WatchCommand {
    /// Start auth sync watcher in background
    Start,

    /// Stop background auth sync watcher
    Stop,

    /// Print watcher status
    Status,

    /// Run watcher loop in foreground
    Run,
}

#[derive(Debug, Clone)]
struct AuthPaths {
    codex_directory: PathBuf,
    codex_auth_file: PathBuf,
    codex_auth_lock_file: PathBuf,
    manager_directory: PathBuf,
    profiles_directory: PathBuf,
    active_account_id_file: PathBuf,
    legacy_profiles_directory: PathBuf,
}

impl AuthPaths {
    fn new(home_directory: PathBuf) -> Self {
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
struct ValidatedAuthFile {
    raw_data: Vec<u8>,
    document_json: Value,
    auth_mode: String,
    account_id: String,
}

#[derive(Debug)]
struct SessionInvalidationResult {
    terminated_app_pids: Vec<i32>,
    terminated_cli_pids: Vec<i32>,
    failed_pids: Vec<i32>,
}

impl SessionInvalidationResult {
    fn had_targets(&self) -> bool {
        !self.terminated_app_pids.is_empty()
            || !self.terminated_cli_pids.is_empty()
            || !self.failed_pids.is_empty()
    }
}

#[derive(Debug)]
struct SwitchResult {
    destination: PathBuf,
    source_description: String,
    invalidation: SessionInvalidationResult,
}

struct FileLock {
    file: File,
}

impl FileLock {
    fn acquire(lock_file: &Path) -> Result<Self> {
        if let Some(parent) = lock_file.parent() {
            create_directory_if_needed(parent, 0o700)?;
        }

        let file = OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .open(lock_file)
            .with_context(|| format!("Failed to open lock file: {}", lock_file.display()))?;
        set_file_permissions(lock_file, 0o600)?;

        file.lock_exclusive()
            .with_context(|| format!("Failed to lock auth file: {}", lock_file.display()))?;

        Ok(Self { file })
    }
}

impl Drop for FileLock {
    fn drop(&mut self) {
        let _ = self.file.unlock();
    }
}

#[derive(Debug)]
struct ProfileManager {
    paths: AuthPaths,
}

impl ProfileManager {
    fn new(home_directory: PathBuf) -> Self {
        Self {
            paths: AuthPaths::new(home_directory),
        }
    }

    fn ensure_directories(&self) -> Result<()> {
        create_directory_if_needed(&self.paths.codex_directory, 0o700)?;
        self.migrate_legacy_profiles_if_needed()?;
        create_directory_if_needed(&self.paths.manager_directory, 0o700)?;
        create_directory_if_needed(&self.paths.profiles_directory, 0o700)?;
        Ok(())
    }

    fn list_profiles(&self) -> Result<Vec<String>> {
        self.ensure_directories()?;
        list_profile_names(&self.paths.profiles_directory)
    }

    fn save_profile(&self, name: &str, source: ProfileSource) -> Result<String> {
        let normalized_name = normalize_profile_name(name)?;
        self.ensure_directories()?;

        let profile_path = profile_path_for(&self.paths.profiles_directory, &normalized_name);
        if profile_path.exists() {
            bail!(
                "A profile with the same normalized name already exists: '{}'.",
                normalized_name
            );
        }

        let current_auth =
            read_validated_auth_file(&self.paths.codex_auth_file).with_context(|| {
                format!(
                    "Cannot save profile because current Codex token is missing or invalid at {}.",
                    self.paths.codex_auth_file.display()
                )
            })?;

        let payload = match source {
            ProfileSource::Current => current_auth.clone(),
            ProfileSource::Path(path) => read_validated_auth_file(&path)?,
        };

        self.ensure_unique_profile_account(&normalized_name, &payload.account_id)?;

        write_secure_atomically(&payload.raw_data, &profile_path)?;
        if payload.account_id == current_auth.account_id {
            self.write_active_account_id(&payload.account_id)?;
        }

        Ok(normalized_name)
    }

    fn remove_profile(&self, name: &str) -> Result<()> {
        let normalized_name = normalize_profile_name(name)?;
        let profile_path = profile_path_for(&self.paths.profiles_directory, &normalized_name);
        if !profile_path.exists() {
            bail!("Profile '{}' was not found.", normalized_name);
        }

        let removed = read_validated_auth_file(&profile_path)?;
        fs::remove_file(&profile_path)
            .with_context(|| format!("failed removing {}", profile_path.display()))?;

        if self.read_active_account_id().as_deref() == Some(&removed.account_id)
            && self
                .profile_name_for_account_id(&removed.account_id)?
                .is_none()
        {
            self.clear_active_account_id()?;
        }

        Ok(())
    }

    fn apply_profile(&self, name: &str) -> Result<SwitchResult> {
        let normalized_name = normalize_profile_name(name)?;
        let profile_path = profile_path_for(&self.paths.profiles_directory, &normalized_name);
        if !profile_path.exists() {
            bail!("Profile '{}' was not found.", normalized_name);
        }

        let payload = read_validated_auth_file(&profile_path)?;
        self.apply_validated_auth(
            payload,
            format!("profile '{}'", normalized_name),
            Some(self.read_validated_auth_account_id(&profile_path)?),
        )
    }

    fn apply_auth_file(&self, path: &Path) -> Result<SwitchResult> {
        let payload = read_validated_auth_file(path)?;
        let account_id = payload.account_id.clone();
        self.apply_validated_auth(payload, path.display().to_string(), Some(account_id))
    }

    fn current_profile_name(&self) -> Result<Option<String>> {
        let current = read_validated_auth_file(&self.paths.codex_auth_file)?;
        self.profile_name_for_account_id(&current.account_id)
    }

    fn current_auth_document(&self) -> Result<ValidatedAuthFile> {
        read_validated_auth_file(&self.paths.codex_auth_file)
    }

    fn sync_active_profile_with_current_auth(&self) -> Result<bool> {
        self.ensure_directories()?;

        let Some(active_account_id) = self.read_active_account_id() else {
            return Ok(false);
        };

        let current = read_validated_auth_file(&self.paths.codex_auth_file)?;
        if current.account_id != active_account_id {
            return Ok(false);
        }

        let Some(active_name) = self.profile_name_for_account_id(&active_account_id)? else {
            self.clear_active_account_id()?;
            return Ok(false);
        };

        let profile_path = profile_path_for(&self.paths.profiles_directory, &active_name);
        let existing = read_validated_auth_file(&profile_path)?;

        if existing.document_json == current.document_json {
            return Ok(false);
        }

        write_secure_atomically(&current.raw_data, &profile_path)?;
        Ok(true)
    }

    fn apply_validated_auth(
        &self,
        payload: ValidatedAuthFile,
        source_description: String,
        active_account_id: Option<String>,
    ) -> Result<SwitchResult> {
        self.ensure_directories()?;
        let _lock = FileLock::acquire(&self.paths.codex_auth_lock_file)?;

        write_secure_atomically(&payload.raw_data, &self.paths.codex_auth_file)?;
        if let Some(account_id) = active_account_id {
            self.write_active_account_id(&account_id)?;
        } else {
            self.clear_active_account_id()?;
        }

        let invalidation = invalidate_running_codex_sessions();

        Ok(SwitchResult {
            destination: self.paths.codex_auth_file.clone(),
            source_description,
            invalidation,
        })
    }

    fn ensure_unique_profile_account(&self, normalized_name: &str, account_id: &str) -> Result<()> {
        for name in self.list_profiles()? {
            if name == normalized_name {
                continue;
            }
            let path = profile_path_for(&self.paths.profiles_directory, &name);
            let existing = read_validated_auth_file(&path)?;
            if existing.account_id == account_id {
                bail!("A profile for this account already exists: '{}'.", name);
            }
        }
        Ok(())
    }

    fn profile_name_for_account_id(&self, account_id: &str) -> Result<Option<String>> {
        for name in self.list_profiles()? {
            let path = profile_path_for(&self.paths.profiles_directory, &name);
            let profile = read_validated_auth_file(&path)?;
            if profile.account_id == account_id {
                return Ok(Some(name));
            }
        }
        Ok(None)
    }

    fn read_active_account_id(&self) -> Option<String> {
        let data = fs::read(&self.paths.active_account_id_file).ok()?;
        let text = String::from_utf8(data).ok()?;
        let value = text.trim();
        if value.is_empty() {
            None
        } else {
            Some(value.to_string())
        }
    }

    fn write_active_account_id(&self, account_id: &str) -> Result<()> {
        write_secure_atomically(account_id.as_bytes(), &self.paths.active_account_id_file)
    }

    fn clear_active_account_id(&self) -> Result<()> {
        if self.paths.active_account_id_file.exists() {
            fs::remove_file(&self.paths.active_account_id_file).with_context(|| {
                format!(
                    "failed removing {}",
                    self.paths.active_account_id_file.display()
                )
            })?;
        }
        Ok(())
    }

    fn migrate_legacy_profiles_if_needed(&self) -> Result<()> {
        if !self.paths.legacy_profiles_directory.exists() {
            return Ok(());
        }

        create_directory_if_needed(&self.paths.manager_directory, 0o700)?;
        create_directory_if_needed(&self.paths.profiles_directory, 0o700)?;

        for entry in fs::read_dir(&self.paths.legacy_profiles_directory).with_context(|| {
            format!(
                "failed to read {}",
                self.paths.legacy_profiles_directory.display()
            )
        })? {
            let entry = entry?;
            let path = entry.path();
            if path.extension() != Some(OsStr::new("json")) {
                continue;
            }

            let destination = self
                .paths
                .profiles_directory
                .join(path.file_name().unwrap());
            if destination.exists() {
                continue;
            }

            fs::copy(&path, &destination).with_context(|| {
                format!(
                    "failed copying legacy profile {} to {}",
                    path.display(),
                    destination.display()
                )
            })?;
            set_file_permissions(&destination, 0o600)?;
        }

        Ok(())
    }

    fn read_validated_auth_account_id(&self, path: &Path) -> Result<String> {
        Ok(read_validated_auth_file(path)?.account_id)
    }
}

#[derive(Debug, Clone)]
enum ProfileSource {
    Current,
    Path(PathBuf),
}

#[derive(Debug, Clone, Eq, PartialEq)]
struct FileSnapshot {
    modification_secs: i64,
    modification_nanos: i64,
    size: i64,
    inode: i64,
}

#[derive(Debug, Clone, Eq, PartialEq)]
enum WatcherStatus {
    Stopped,
    Running(i32),
}

struct AuthSyncWatcher {
    manager: ProfileManager,
    auth_file_path: PathBuf,
    state_directory: PathBuf,
    pid_file_path: PathBuf,
    log_file_path: PathBuf,
}

impl AuthSyncWatcher {
    fn new(home_directory: PathBuf) -> Self {
        let manager = ProfileManager::new(home_directory);
        let auth_file_path = manager.paths.codex_auth_file.clone();
        let state_directory = manager.paths.manager_directory.clone();
        let pid_file_path = state_directory.join("codex-auth-watch.pid");
        let log_file_path = state_directory.join("codex-auth-watch.log");

        Self {
            manager,
            auth_file_path,
            state_directory,
            pid_file_path,
            log_file_path,
        }
    }

    fn status(&self) -> WatcherStatus {
        let Some(pid) = self.read_pid() else {
            return WatcherStatus::Stopped;
        };

        if is_process_running(pid) {
            WatcherStatus::Running(pid)
        } else {
            self.clear_pid_file_if_present();
            WatcherStatus::Stopped
        }
    }

    fn start_daemon(&self, executable_path: &Path, home_directory: &Path) -> Result<i32> {
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
        cmd.arg("--home")
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

    fn stop_daemon(&self) -> Result<()> {
        let Some(pid) = self.read_pid() else {
            return Ok(());
        };

        let rc = unsafe { libc::kill(pid, libc::SIGTERM) };
        if rc != 0 {
            self.clear_pid_file_if_present();
            bail!("Failed to stop watcher: could not signal process {}", pid);
        }

        self.clear_pid_file_if_present();
        Ok(())
    }

    fn run_loop(&self) -> Result<()> {
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
}

#[derive(Copy, Clone, Eq, PartialEq)]
enum SessionKind {
    App,
    Cli,
}

fn invalidate_running_codex_sessions() -> SessionInvalidationResult {
    request_codex_app_quit();

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

        if let Some(existing) = targets.get(&pid) {
            if *existing == SessionKind::App {
                continue;
            }
        }
        targets.insert(pid, kind);
    }

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

fn request_codex_app_quit() {
    #[cfg(target_os = "macos")]
    {
        let _ = Command::new("/usr/bin/osascript")
            .args(["-e", "tell application \"Codex\" to quit"])
            .output();
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
    if command.contains("/Codex.app/Contents/") {
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

fn is_process_running(pid: i32) -> bool {
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

fn is_executable(path: &Path) -> bool {
    if let Ok(metadata) = fs::metadata(path) {
        metadata.permissions().mode() & 0o111 != 0
    } else {
        false
    }
}

fn normalize_profile_name(name: &str) -> Result<String> {
    let trimmed = name.trim();
    if trimmed.is_empty() {
        bail!(
            "Invalid profile name '{}'. Use at least one letter or number; names are normalized to lowercase-with-dashes.",
            name
        );
    }

    let mut normalized = String::new();
    let mut previous_was_separator = false;

    for ch in trimmed.chars() {
        if ch.is_alphanumeric() {
            for lower in ch.to_lowercase() {
                normalized.push(lower);
            }
            previous_was_separator = false;
        } else if !normalized.is_empty() && !previous_was_separator {
            normalized.push('-');
            previous_was_separator = true;
        }
    }

    while normalized.ends_with('-') {
        normalized.pop();
    }

    if normalized.is_empty() {
        bail!(
            "Invalid profile name '{}'. Use at least one letter or number; names are normalized to lowercase-with-dashes.",
            name
        );
    }

    Ok(normalized)
}

fn create_directory_if_needed(path: &Path, mode: u32) -> Result<()> {
    if !path.exists() {
        fs::create_dir_all(path).with_context(|| format!("failed creating {}", path.display()))?;
    }
    set_file_permissions(path, mode)
}

fn set_file_permissions(path: &Path, mode: u32) -> Result<()> {
    let perms = fs::Permissions::from_mode(mode);
    fs::set_permissions(path, perms)
        .with_context(|| format!("Failed setting secure permissions on {}", path.display()))?;
    Ok(())
}

fn list_profile_names(profiles_dir: &Path) -> Result<Vec<String>> {
    let mut names = Vec::new();

    for entry in fs::read_dir(profiles_dir)
        .with_context(|| format!("failed reading {}", profiles_dir.display()))?
    {
        let entry = entry?;
        let path = entry.path();
        if path.extension() != Some(OsStr::new("json")) {
            continue;
        }

        let Some(stem) = path.file_stem().and_then(|s| s.to_str()) else {
            continue;
        };

        names.push(stem.to_string());
    }

    names.sort();
    Ok(names)
}

fn profile_path_for(profiles_dir: &Path, name: &str) -> PathBuf {
    profiles_dir.join(format!("{name}.json"))
}

fn read_validated_auth_file(path: &Path) -> Result<ValidatedAuthFile> {
    if !path.exists() {
        bail!("File not found: {}", path.display());
    }

    let raw_data = fs::read(path).with_context(|| format!("failed reading {}", path.display()))?;
    let document_json: Value = serde_json::from_slice(&raw_data).map_err(|_| {
        anyhow::anyhow!(
            "Invalid auth file at {}. Expected Codex auth.json format.",
            path.display()
        )
    })?;

    let auth_mode = document_json
        .get("auth_mode")
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    let account_id = document_json
        .get("tokens")
        .and_then(Value::as_object)
        .and_then(|tokens| tokens.get("account_id"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    let id_token = document_json
        .get("tokens")
        .and_then(Value::as_object)
        .and_then(|tokens| tokens.get("id_token"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    let access_token = document_json
        .get("tokens")
        .and_then(Value::as_object)
        .and_then(|tokens| tokens.get("access_token"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    let refresh_token = document_json
        .get("tokens")
        .and_then(Value::as_object)
        .and_then(|tokens| tokens.get("refresh_token"))
        .and_then(Value::as_str)
        .unwrap_or_default()
        .trim()
        .to_string();

    if auth_mode.is_empty()
        || id_token.is_empty()
        || access_token.is_empty()
        || refresh_token.is_empty()
        || account_id.is_empty()
    {
        bail!(
            "Invalid auth file at {}. Expected Codex auth.json format.",
            path.display()
        );
    }

    Ok(ValidatedAuthFile {
        raw_data,
        document_json,
        auth_mode,
        account_id,
    })
}

fn write_secure_atomically(data: &[u8], destination: &Path) -> Result<()> {
    let Some(parent) = destination.parent() else {
        bail!("invalid destination path: {}", destination.display());
    };
    create_directory_if_needed(parent, 0o700)?;

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0));
    let tmp = parent.join(format!(
        ".tmp-{}-{}-{}",
        std::process::id(),
        now.as_nanos(),
        destination
            .file_name()
            .and_then(OsStr::to_str)
            .unwrap_or("auth")
    ));

    let mut file = OpenOptions::new()
        .create_new(true)
        .write(true)
        .open(&tmp)
        .with_context(|| format!("Failed to create temporary auth file at {}", tmp.display()))?;

    if let Err(error) = (|| -> Result<()> {
        file.write_all(data)
            .with_context(|| format!("failed writing {}", tmp.display()))?;
        file.flush().ok();
        set_file_permissions(&tmp, 0o600)?;
        fs::rename(&tmp, destination).with_context(|| {
            format!(
                "Failed replacing {} with temporary auth file {}",
                destination.display(),
                tmp.display()
            )
        })?;
        set_file_permissions(destination, 0o600)?;
        Ok(())
    })() {
        let _ = fs::remove_file(&tmp);
        return Err(error);
    }

    Ok(())
}

fn print_profiles(manager: &ProfileManager, plain: bool) -> Result<()> {
    let current = manager.current_profile_name()?;
    let profiles = manager.list_profiles()?;

    if profiles.is_empty() {
        if !plain {
            println!("No saved profiles");
        }
        return Ok(());
    }

    if plain {
        for name in profiles {
            println!("{name}");
        }
        return Ok(());
    }

    println!("Profiles:");
    for name in profiles {
        if current.as_deref() == Some(name.as_str()) {
            println!("* {name}");
        } else {
            println!("  {name}");
        }
    }

    Ok(())
}

fn print_use_result(result: SwitchResult) {
    println!("Applied auth from {}", result.source_description);
    println!("Updated: {}", result.destination.display());

    if result.invalidation.had_targets() {
        println!("Invalidated Codex sessions:");
        println!(
            "  app processes terminated: {}",
            result.invalidation.terminated_app_pids.len()
        );
        println!(
            "  cli processes terminated: {}",
            result.invalidation.terminated_cli_pids.len()
        );

        if !result.invalidation.terminated_app_pids.is_empty() {
            println!(
                "  app PIDs: {}",
                join_i32(&result.invalidation.terminated_app_pids)
            );
        }
        if !result.invalidation.terminated_cli_pids.is_empty() {
            println!(
                "  cli PIDs: {}",
                join_i32(&result.invalidation.terminated_cli_pids)
            );
        }
        if !result.invalidation.failed_pids.is_empty() {
            println!(
                "  failed to terminate PIDs: {}",
                join_i32(&result.invalidation.failed_pids)
            );
        }
    } else {
        println!("No running Codex app/CLI sessions were detected.");
    }
}

fn join_i32(values: &[i32]) -> String {
    values
        .iter()
        .map(|v| v.to_string())
        .collect::<Vec<String>>()
        .join(", ")
}

fn masked(value: &str) -> String {
    if value.chars().count() <= 8 {
        return "*".repeat(value.chars().count());
    }

    let prefix: String = value.chars().take(4).collect();
    let suffix: String = value
        .chars()
        .rev()
        .take(4)
        .collect::<String>()
        .chars()
        .rev()
        .collect();
    format!("{prefix}...{suffix}")
}

fn resolve_home(override_home: Option<PathBuf>) -> Result<PathBuf> {
    if let Some(path) = override_home {
        return Ok(expand_tilde(path));
    }

    let home = std::env::var("HOME").context("HOME is not set")?;
    Ok(PathBuf::from(home))
}

fn expand_tilde(path: PathBuf) -> PathBuf {
    let raw = path.to_string_lossy();
    if raw == "~" || raw.starts_with("~/") {
        if let Ok(home) = std::env::var("HOME") {
            if raw == "~" {
                return PathBuf::from(home);
            }
            return PathBuf::from(home).join(raw.trim_start_matches("~/"));
        }
    }
    path
}

fn run() -> Result<()> {
    let cli = Cli::parse();
    let home = resolve_home(cli.home)?;
    let manager = ProfileManager::new(home.clone());

    match cli.command {
        Commands::Save(args) => {
            let source = if let Some(path) = args.path {
                ProfileSource::Path(expand_tilde(path))
            } else {
                let _ = args.from_current;
                ProfileSource::Current
            };

            let before = manager.list_profiles()?;
            if before.is_empty() {
                println!("Existing profiles: (none)");
            } else {
                println!("Existing profiles: {}", before.join(", "));
            }

            let saved_name = manager.save_profile(&args.profile, source)?;
            println!("Saved profile '{saved_name}'");

            let after = manager.list_profiles()?;
            println!("Available profiles: {}", after.join(", "));
        }
        Commands::Use(args) => match (args.profile, args.path) {
            (Some(_), Some(_)) => {
                bail!("Use either <profile> or --path <auth.json>, not both")
            }
            (None, None) => {
                bail!("Missing profile name or --path option")
            }
            (Some(profile), None) => {
                let result = manager.apply_profile(&profile)?;
                print_use_result(result);
            }
            (None, Some(path)) => {
                let path = expand_tilde(path);
                let result = manager.apply_auth_file(&path)?;
                print_use_result(result);
            }
        },
        Commands::List(args) => {
            print_profiles(&manager, args.plain)?;
        }
        Commands::Current(args) => {
            if args.plain {
                if let Some(current_profile) = manager.current_profile_name()? {
                    println!("{current_profile}");
                }
            } else {
                let current_profile = manager
                    .current_profile_name()?
                    .unwrap_or_else(|| "(untracked)".to_string());
                println!("Current profile: {current_profile}");

                let document = manager.current_auth_document()?;
                println!("auth_mode: {}", document.auth_mode);
                println!("account_id: {}", masked(&document.account_id));
            }
        }
        Commands::Remove(args) => {
            let normalized = normalize_profile_name(&args.profile)?;
            manager.remove_profile(&args.profile)?;
            println!("Removed profile '{normalized}'");
            print_profiles(&manager, false)?;
        }
        Commands::Watch { action } => {
            let watcher = AuthSyncWatcher::new(home.clone());
            match action {
                WatchCommand::Start => {
                    let executable =
                        std::env::current_exe().context("failed to resolve current executable")?;
                    let pid = watcher.start_daemon(&executable, &home)?;
                    println!("Watcher running (PID {pid})");
                }
                WatchCommand::Stop => {
                    watcher.stop_daemon()?;
                    println!("Watcher stopped");
                }
                WatchCommand::Status => match watcher.status() {
                    WatcherStatus::Stopped => println!("Watcher stopped"),
                    WatcherStatus::Running(pid) => println!("Watcher running (PID {pid})"),
                },
                WatchCommand::Run => {
                    watcher.run_loop()?;
                }
            }
        }
    }

    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("Error: {error}");
        std::process::exit(1);
    }
}
