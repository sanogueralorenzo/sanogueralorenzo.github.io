use crate::adapters::session_store::{SessionStore, resolve_session_by_id};
use crate::cli::{
    ArchiveArgs, Cli, Commands, DeleteArgs, GenerateThreadTitleArgs, ListArgs, MergeArgs,
    MessageArgs, PruneArgs, ShowArgs, SortBy, TitlesArgs, UnarchiveArgs, WatchArgs,
    WatchTitleCommand,
};
use crate::services::session_service::{
    age_days, prune_sessions, to_output_entries, to_output_entry, validate_days,
};
use crate::shared::models::{
    DeleteResult, ListResult, MergeResult, MessageResult, OperationBatchResult, PruneResult,
    SessionMeta, TitleResult,
};
use crate::shared::output::OutputFormat;
use anyhow::{Context, Result, bail};
use clap::Parser;
use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};
use std::fs::{self, OpenOptions};
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::thread;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

const TITLE_MIN_CHARS: usize = 18;
const TITLE_MAX_CHARS: usize = 36;
const TITLE_INPUT_MAX_CHARS: usize = 2000;
const TITLE_MODEL: &str = "gpt-5.1-codex-mini";
const WATCH_TITLE_INTERVAL: Duration = Duration::from_secs(10);
const WATCH_TITLE_BATCH_LIMIT: usize = 100;
const WATCH_TITLE_PID_FILE: &str = "codex-sessions-watch-title.pid";
const WATCH_TITLE_LOG_FILE: &str = "codex-sessions-watch-title.log";
const WATCH_TITLE_STATE_FILE: &str = "codex-sessions-watch-title.state.json";

pub fn run() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::List(args) => cmd_list(args),
        Commands::Titles(args) => cmd_titles(args),
        Commands::GenerateThreadTitle(args) => cmd_generate_thread_title(args),
        Commands::Show(args) => cmd_show(args),
        Commands::Message(args) => cmd_message(args),
        Commands::Delete(args) => cmd_delete(args),
        Commands::Archive(args) => cmd_archive(args),
        Commands::Unarchive(args) => cmd_unarchive(args),
        Commands::Merge(args) => cmd_merge(args),
        Commands::Prune(args) => cmd_prune(args),
        Commands::Watch(args) => cmd_watch(args),
        Commands::WatchTitle { action } => cmd_watch_title(action),
    }
}

fn cmd_list(args: ListArgs) -> Result<()> {
    let ListArgs {
        home,
        limit,
        cursor,
        older_than_days,
        archived,
        all,
        cwd,
        source_kinds,
        sort_by,
        folders,
        search,
        json,
        plain,
    } = args;

    let store = SessionStore::new(home)?;
    let mut sessions = store.collect_sessions()?;

    sessions.retain(|session| session.archived == archived);

    if let Some(days) = older_than_days {
        validate_days(days)?;
        sessions.retain(|session| age_days(session.last_updated_at) >= days);
    }

    if let Some(cwd_filter) = resolve_cwd_filter(all, cwd.as_deref())? {
        sessions.retain(|session| session.cwd.as_deref() == Some(cwd_filter.as_str()));
    }

    if !source_kinds.is_empty() {
        let allowed: HashSet<String> = source_kinds
            .iter()
            .map(|value| value.as_stored().to_string())
            .collect();
        sessions.retain(|session| allowed.contains(&session.source_kind));
    }

    if let Some(search) = search.as_deref() {
        let needle = search.trim().to_ascii_lowercase();
        if !needle.is_empty() {
            sessions.retain(|session| matches_search(session, &needle));
        }
    }

    if folders {
        sort_sessions_by_folder_then_updated(&mut sessions);
    } else {
        sort_sessions(&mut sessions, sort_by);
    }

    let start = resolve_cursor_start(&sessions, cursor.as_deref())?;
    let remaining = if start >= sessions.len() {
        Vec::new()
    } else {
        sessions[start..].to_vec()
    };

    let limit = limit.unwrap_or(remaining.len());
    let page_size = remaining.len().min(limit);
    let page = remaining[..page_size].to_vec();
    let next_cursor = if remaining.len() > page_size {
        page.last().map(|session| session.id.clone())
    } else {
        None
    };

    let output = to_output_entries(&page);
    let response = ListResult {
        data: output,
        next_cursor,
    };

    if json {
        println!("{}", serde_json::to_string_pretty(&response)?);
        return Ok(());
    }

    if plain {
        for item in &response.data {
            let title = item.title.clone().unwrap_or_default();
            let cwd = item.cwd.clone().unwrap_or_default();
            let source = item.source.clone().unwrap_or_default();
            println!(
                "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
                item.id,
                item.last_updated_at,
                item.age_days,
                item.relative_path,
                source,
                item.source_kind,
                item.archived,
                cwd,
                title
            );
        }
        if let Some(cursor) = response.next_cursor {
            println!("next_cursor\t{cursor}");
        }
        return Ok(());
    }

    if response.data.is_empty() {
        println!("No Codex sessions found.");
        return Ok(());
    }

    println!("Found {} session(s):", response.data.len());
    for item in &response.data {
        let title = item
            .title
            .clone()
            .unwrap_or_else(|| "(no title)".to_string());
        let cwd = item
            .cwd
            .clone()
            .unwrap_or_else(|| "(unknown cwd)".to_string());
        println!(
            "- {} | {} | {}d | {} | {} | {} | {}",
            item.id,
            item.last_updated_at,
            item.age_days,
            item.source_kind,
            if item.archived { "archived" } else { "active" },
            cwd,
            title
        );
    }
    if let Some(cursor) = response.next_cursor {
        println!("Next cursor: {cursor}");
    }

    Ok(())
}

fn cmd_titles(args: TitlesArgs) -> Result<()> {
    let store = SessionStore::new(args.home)?;
    let sessions = store.collect_sessions()?;
    let mut titles = std::collections::HashMap::new();
    for session in sessions {
        if let Some(title) = session.title {
            let cleaned = title.trim();
            if cleaned.is_empty() {
                continue;
            }
            titles.insert(session.id, cleaned.to_string());
        }
    }

    if args.json {
        println!("{}", serde_json::to_string_pretty(&titles)?);
        return Ok(());
    }

    let mut entries: Vec<(String, String)> = titles.into_iter().collect();
    entries.sort_by(|a, b| a.0.cmp(&b.0));

    if args.plain {
        for (id, title) in entries {
            println!("{id}\t{title}");
        }
        return Ok(());
    }

    if entries.is_empty() {
        println!("No session titles found.");
        return Ok(());
    }

    println!("Found {} title(s):", entries.len());
    for (id, title) in entries {
        println!("- {id} | {title}");
    }

    Ok(())
}

fn cmd_generate_thread_title(args: GenerateThreadTitleArgs) -> Result<()> {
    let store = SessionStore::new(args.home)?;
    let sessions = store.collect_sessions()?;
    let target = resolve_session_by_id(&sessions, &args.id)?;

    let first_user_prompt = store
        .read_first_user_message(target)?
        .ok_or_else(|| anyhow::anyhow!("no first user prompt found for session {}", target.id))?;

    if store
        .read_latest_assistant_message(&target.file_path)?
        .is_none()
    {
        bail!(
            "session {} has no assistant response yet; generate title only after first completed turn",
            target.id
        );
    }

    let title = generate_session_title(target, &first_user_prompt)?;
    store.set_thread_title(&target.id, &title)?;

    let result = TitleResult {
        id: target.id.clone(),
        title,
    };

    emit_title_output(result, args.json, args.plain)
}

fn cmd_show(args: ShowArgs) -> Result<()> {
    let store = SessionStore::new(args.home)?;
    let result = with_target_session(&store, &args.id, |target| Ok(to_output_entry(target)))?;

    if args.json {
        println!("{}", serde_json::to_string_pretty(&result)?);
    } else if args.plain {
        let title = result.title.unwrap_or_default();
        let cwd = result.cwd.unwrap_or_default();
        let source = result.source.unwrap_or_default();
        println!(
            "{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}",
            result.id,
            result.created_at,
            result.last_updated_at,
            result.age_days,
            result.relative_path,
            result.size_bytes,
            source,
            result.source_kind,
            result.archived,
            cwd,
            title
        );
    } else {
        println!("Session: {}", result.id);
        println!("Created: {}", result.created_at);
        println!("Updated: {}", result.last_updated_at);
        println!("Age: {} day(s)", result.age_days);
        println!("Path: {}", result.file_path);
        println!("Relative path: {}", result.relative_path);
        println!("Size: {} bytes", result.size_bytes);
        println!("Source kind: {}", result.source_kind);
        println!(
            "Source: {}",
            result.source.unwrap_or_else(|| "(unknown)".to_string())
        );
        println!("Archived: {}", result.archived);
        println!(
            "CWD: {}",
            result.cwd.unwrap_or_else(|| "(unknown)".to_string())
        );
        println!(
            "Title: {}",
            result.title.unwrap_or_else(|| "(no title)".to_string())
        );
    }

    Ok(())
}

fn cmd_message(args: MessageArgs) -> Result<()> {
    let store = SessionStore::new(args.home)?;
    let result = with_target_session(&store, &args.id, |target| {
        let latest = store.read_latest_assistant_message(&target.file_path)?;
        Ok(MessageResult {
            id: target.id.clone(),
            message: latest,
        })
    })?;

    if args.json {
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(());
    }

    if args.plain {
        if let Some(message) = result.message {
            println!("{message}");
        }
        return Ok(());
    }

    match result.message {
        Some(message) => {
            println!("Latest assistant message for {}:", result.id);
            println!("{message}");
        }
        None => {
            println!("No assistant message found for {}", result.id);
        }
    }

    Ok(())
}

fn cmd_delete(args: DeleteArgs) -> Result<()> {
    validate_delete_args(&args)?;
    let store = SessionStore::new(args.home.clone())?;
    let sessions = store.collect_sessions()?;
    let targets = resolve_delete_targets(&sessions, &args)?;

    let action_name = if args.hard { "delete" } else { "archive" };

    let results = if args.dry_run {
        targets
            .iter()
            .map(|target| DeleteResult {
                deleted: false,
                id: target.id.clone(),
                file_path: target.file_path.display().to_string(),
                action: if args.hard {
                    "deleted".to_string()
                } else {
                    "archived".to_string()
                },
                error: None,
            })
            .collect()
    } else if args.hard {
        store.delete_sessions_hard(&targets)?
    } else {
        let mut archived = Vec::with_capacity(targets.len());
        for target in &targets {
            archived.push(store.archive_session(target)?);
        }
        archived
    };

    let response = build_operation_batch_result(action_name, args.dry_run, args.hard, results);
    if response.processed == 1
        && args.ids.len() == 1
        && !has_selector_flags(&args)
        && response.failed == 0
    {
        let mut sessions = response.sessions;
        return emit_delete_output(sessions.remove(0), args.json, args.plain);
    }
    emit_operation_batch_output(response, args.json, args.plain)
}

fn cmd_archive(args: ArchiveArgs) -> Result<()> {
    let store = SessionStore::new(args.home.clone())?;
    let sessions = store.collect_sessions()?;
    let targets = resolve_targets_for_inputs(&sessions, &args.ids)?;

    let mut results = Vec::with_capacity(targets.len());
    for target in targets {
        results.push(store.archive_session(target)?);
    }

    let response = build_operation_batch_result("archive", false, false, results);
    if response.processed == 1 && args.ids.len() == 1 && response.failed == 0 {
        let mut sessions = response.sessions;
        return emit_delete_output(sessions.remove(0), args.json, args.plain);
    }
    emit_operation_batch_output(response, args.json, args.plain)
}

fn cmd_unarchive(args: UnarchiveArgs) -> Result<()> {
    let store = SessionStore::new(args.home.clone())?;
    let sessions = store.collect_sessions()?;
    let targets = resolve_targets_for_inputs(&sessions, &args.ids)?;

    let mut results = Vec::with_capacity(targets.len());
    for target in targets {
        results.push(store.unarchive_session(target)?);
    }

    let response = build_operation_batch_result("unarchive", false, false, results);
    if response.processed == 1 && args.ids.len() == 1 && response.failed == 0 {
        let mut sessions = response.sessions;
        return emit_delete_output(sessions.remove(0), args.json, args.plain);
    }
    emit_operation_batch_output(response, args.json, args.plain)
}

fn build_operation_batch_result(
    action: &str,
    dry_run: bool,
    hard: bool,
    sessions: Vec<DeleteResult>,
) -> OperationBatchResult {
    let processed = sessions.len();
    let failed = sessions
        .iter()
        .filter(|session| session.error.is_some())
        .count();
    let succeeded = sessions
        .iter()
        .filter(|session| session.error.is_none() && session.deleted)
        .count();
    let skipped = sessions
        .iter()
        .filter(|session| session.error.is_none() && !session.deleted)
        .count();

    OperationBatchResult {
        action: action.to_string(),
        dry_run,
        hard,
        processed,
        succeeded,
        failed,
        skipped,
        sessions,
    }
}

fn cmd_merge(args: MergeArgs) -> Result<()> {
    let target_id = args.target.trim().to_string();
    let merge_id = args.merge.trim().to_string();
    if target_id.is_empty() {
        bail!("--target cannot be empty");
    }
    if merge_id.is_empty() {
        bail!("--merge cannot be empty");
    }
    if target_id == merge_id {
        bail!("--target and --merge must be different sessions");
    }

    let store = SessionStore::new(args.home)?;
    let sessions = store.collect_sessions()?;
    let target = resolve_session_by_id(&sessions, &target_id)?.clone();
    let merge = resolve_session_by_id(&sessions, &merge_id)?.clone();

    let summary_prompt = build_merger_summary_prompt(&target, &merge);
    let transfer_summary = run_codex_exec_resume_capture_last_message(&merge, &summary_prompt)?;
    let apply_prompt = build_target_apply_prompt(&merge, &transfer_summary);
    run_codex_exec_resume(&target, &apply_prompt)?;

    let deleted = store.delete_session_hard(&merge)?;
    let result = MergeResult {
        target_id: target.id,
        merged_id: merge.id,
        merged_deleted: deleted.deleted,
        merged_file_path: deleted.file_path,
    };

    emit_merge_output(result, args.json, args.plain)
}

fn cmd_prune(args: PruneArgs) -> Result<()> {
    let store = SessionStore::new(args.home)?;
    let format = OutputFormat::from_flags(args.json, args.plain);
    let report = prune_sessions(&store, args.older_than_days, args.dry_run, args.hard)?;
    emit_prune_output(&report, format)
}

fn cmd_watch(args: WatchArgs) -> Result<()> {
    validate_days(args.older_than_days)?;
    if args.interval_minutes == 0 {
        bail!("--interval-minutes must be >= 1");
    }

    let store = SessionStore::new(args.home)?;
    let format = OutputFormat::from_flags(args.json, args.plain);
    let interval = Duration::from_secs(args.interval_minutes * 60);

    loop {
        let report = prune_sessions(&store, args.older_than_days, args.dry_run, args.hard)?;
        emit_prune_output(&report, format)?;

        if args.once {
            break;
        }

        if !args.json && !args.plain {
            println!(
                "Waiting {} minute(s) before next prune...",
                args.interval_minutes
            );
        }

        thread::sleep(interval);
    }

    Ok(())
}

fn cmd_watch_title(action: WatchTitleCommand) -> Result<()> {
    match action {
        WatchTitleCommand::Start(args) => {
            let watcher = TitleWatcher::new(args.home)?;
            let executable =
                std::env::current_exe().context("failed to resolve current executable")?;
            let pid = watcher.start_daemon(&executable)?;
            println!("Title watcher running (PID {pid})");
        }
        WatchTitleCommand::Stop(args) => {
            let watcher = TitleWatcher::new(args.home)?;
            watcher.stop_daemon()?;
            println!("Title watcher stopped");
        }
        WatchTitleCommand::Status(args) => {
            let watcher = TitleWatcher::new(args.home)?;
            match watcher.status() {
                TitleWatcherStatus::Stopped => println!("Title watcher stopped"),
                TitleWatcherStatus::Running(pid) => {
                    println!("Title watcher running (PID {pid})")
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
            .arg("watch-title")
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
                "[codex-sessions:watch-title] scanned={} generated={} skipped_non_empty={} skipped_not_ready={} missing={} errors={} watermark_updated_at={} watermark_id={}",
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
                        "[codex-sessions:watch-title] generate failed id={} error={}",
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
                    "[codex-sessions:watch-title] persist failed id={} error={}",
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

fn emit_delete_output(result: DeleteResult, json: bool, plain: bool) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(&result)?);
    } else if plain {
        let error = result.error.clone().unwrap_or_default();
        println!(
            "{}\t{}\t{}\t{}",
            result.id, result.action, result.file_path, error
        );
    } else {
        let is_failed = result.error.is_some();
        match result.action.as_str() {
            "archived" => println!("Archived session {}", result.id),
            "unarchived" => println!("Unarchived session {}", result.id),
            "deleted" if is_failed => println!("Delete incomplete for session {}", result.id),
            _ => println!("Deleted session {}", result.id),
        }
        println!("Path: {}", result.file_path);
        if let Some(error) = result.error {
            println!("Error: {}", error);
        }
    }

    Ok(())
}

fn emit_operation_batch_output(
    result: OperationBatchResult,
    json: bool,
    plain: bool,
) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(());
    }

    if plain {
        println!(
            "{}\t{}\t{}\t{}\t{}\t{}",
            result.action,
            result.processed,
            result.succeeded,
            result.failed,
            result.skipped,
            result.dry_run
        );
        for item in result.sessions {
            let error = item.error.unwrap_or_default();
            println!(
                "{}\t{}\t{}\t{}",
                item.id, item.action, item.file_path, error
            );
        }
        return Ok(());
    }

    let verb = match result.action.as_str() {
        "delete" if result.dry_run => "Would delete",
        "delete" => "Deleted",
        "archive" if result.dry_run => "Would archive",
        "archive" => "Archived",
        "unarchive" if result.dry_run => "Would unarchive",
        "unarchive" => "Unarchived",
        _ => "Processed",
    };
    println!(
        "{} {} session(s). Succeeded: {}. Failed: {}. Skipped: {}.",
        verb, result.processed, result.succeeded, result.failed, result.skipped
    );
    for item in result.sessions {
        if let Some(error) = item.error {
            println!(
                "- {} [{}] ({}) error={}",
                item.id, item.action, item.file_path, error
            );
        } else {
            println!("- {} [{}] ({})", item.id, item.action, item.file_path);
        }
    }
    Ok(())
}

fn emit_prune_output(report: &PruneResult, format: OutputFormat) -> Result<()> {
    match format {
        OutputFormat::Json => {
            println!("{}", serde_json::to_string_pretty(report)?);
        }
        OutputFormat::Plain => {
            println!(
                "{}\t{}\t{}\t{}",
                report.scanned, report.pruned, report.dry_run, report.hard
            );
            for session in &report.sessions {
                let error = session.error.clone().unwrap_or_default();
                println!(
                    "{}\t{}\t{}\t{}",
                    session.id, session.action, session.file_path, error
                );
            }
        }
        OutputFormat::Human => {
            let action = if report.hard { "delete" } else { "archive" };
            let verb = if report.dry_run {
                format!("Would {action}")
            } else if report.hard {
                "Deleted".to_string()
            } else {
                "Archived".to_string()
            };
            println!(
                "{} {} of {} active session(s) older than {} day(s).",
                verb, report.pruned, report.scanned, report.older_than_days
            );
            for session in &report.sessions {
                if let Some(error) = &session.error {
                    println!(
                        "- {} [{}] ({}) error={}",
                        session.id, session.action, session.file_path, error
                    );
                } else {
                    println!(
                        "- {} [{}] ({})",
                        session.id, session.action, session.file_path
                    );
                }
            }
        }
    }

    Ok(())
}

fn emit_merge_output(result: MergeResult, json: bool, plain: bool) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(());
    }

    if plain {
        println!(
            "{}\t{}\t{}\t{}",
            result.target_id, result.merged_id, result.merged_deleted, result.merged_file_path
        );
        return Ok(());
    }

    println!(
        "Merged session {} into session {}.",
        result.merged_id, result.target_id
    );
    println!("Deleted merged session file: {}", result.merged_file_path);
    Ok(())
}

fn emit_title_output(result: TitleResult, json: bool, plain: bool) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(&result)?);
        return Ok(());
    }

    if plain {
        println!("{}\t{}", result.id, result.title);
        return Ok(());
    }

    println!("Updated session title for {}", result.id);
    println!("Title: {}", result.title);
    Ok(())
}

fn with_target_session<T, F>(store: &SessionStore, id: &str, action: F) -> Result<T>
where
    F: FnOnce(&SessionMeta) -> Result<T>,
{
    let sessions = store.collect_sessions()?;
    let target = resolve_session_by_id(&sessions, id)?;
    action(target)
}

fn validate_delete_args(args: &DeleteArgs) -> Result<()> {
    if let Some(days) = args.older_than_days {
        validate_days(days)?;
    }

    let has_ids = !args.ids.is_empty();
    let has_selector = has_selector_flags(args);
    if !has_ids && !has_selector {
        bail!(
            "provide one or more <IDS> or at least one selector flag (--all, --older-than-days, --folder, --search)"
        );
    }
    if has_ids && has_selector {
        bail!("cannot combine explicit <IDS> with selector flags");
    }
    if !has_ids && !args.dry_run && !args.yes {
        bail!("selector-based delete requires --yes (or run with --dry-run)");
    }

    Ok(())
}

fn has_selector_flags(args: &DeleteArgs) -> bool {
    args.all
        || args.older_than_days.is_some()
        || args
            .folder
            .as_deref()
            .map(str::trim)
            .map(|value| !value.is_empty())
            .unwrap_or(false)
        || args
            .search
            .as_deref()
            .map(str::trim)
            .map(|value| !value.is_empty())
            .unwrap_or(false)
}

fn resolve_delete_targets<'a>(
    sessions: &'a [SessionMeta],
    args: &DeleteArgs,
) -> Result<Vec<&'a SessionMeta>> {
    if !args.ids.is_empty() {
        return resolve_targets_for_inputs(sessions, &args.ids);
    }

    let folder_filter = args
        .folder
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_ascii_lowercase());
    let search_filter = args
        .search
        .as_deref()
        .map(str::trim)
        .filter(|value| !value.is_empty())
        .map(|value| value.to_ascii_lowercase());

    let mut targets = Vec::new();
    for session in sessions {
        if session.archived {
            continue;
        }
        if let Some(days) = args.older_than_days {
            if age_days(session.last_updated_at) < days {
                continue;
            }
        }
        if let Some(folder) = folder_filter.as_deref() {
            let session_folder = session_folder_key(session.cwd.as_deref());
            if session_folder != folder {
                continue;
            }
        }
        if let Some(needle) = search_filter.as_deref() {
            if !matches_search(session, needle) {
                continue;
            }
        }
        if !args.all
            && args.older_than_days.is_none()
            && folder_filter.is_none()
            && search_filter.is_none()
        {
            continue;
        }
        targets.push(session);
    }

    Ok(targets)
}

fn resolve_targets_for_inputs<'a>(
    sessions: &'a [SessionMeta],
    inputs: &[String],
) -> Result<Vec<&'a SessionMeta>> {
    let mut seen = HashSet::new();
    let mut targets = Vec::with_capacity(inputs.len());

    for raw in inputs {
        let id = raw.trim();
        if id.is_empty() {
            bail!("session id cannot be empty");
        }
        let target = resolve_session_by_id(sessions, id)?;
        if seen.insert(target.id.clone()) {
            targets.push(target);
        }
    }

    Ok(targets)
}

fn sort_sessions(sessions: &mut [SessionMeta], sort_by: SortBy) {
    match sort_by {
        SortBy::CreatedAt => sessions.sort_by(|a, b| {
            b.created_at
                .cmp(&a.created_at)
                .then_with(|| b.id.cmp(&a.id))
        }),
        SortBy::UpdatedAt => sessions.sort_by(|a, b| {
            b.last_updated_at
                .cmp(&a.last_updated_at)
                .then_with(|| b.id.cmp(&a.id))
        }),
    }
}

fn sort_sessions_by_folder_then_updated(sessions: &mut [SessionMeta]) {
    sessions.sort_by(|a, b| {
        let a_folder = session_folder_key(a.cwd.as_deref());
        let b_folder = session_folder_key(b.cwd.as_deref());
        a_folder
            .cmp(&b_folder)
            .then_with(|| b.last_updated_at.cmp(&a.last_updated_at))
            .then_with(|| b.id.cmp(&a.id))
    });
}

fn session_folder_key(cwd: Option<&str>) -> String {
    let Some(cwd) = cwd else {
        return "unknown".to_string();
    };
    let trimmed = cwd.trim();
    if trimmed.is_empty() {
        return "unknown".to_string();
    }
    std::path::Path::new(trimmed)
        .file_name()
        .and_then(|value| value.to_str())
        .map(|value| value.trim().to_ascii_lowercase())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| trimmed.to_ascii_lowercase())
}

fn resolve_cursor_start(sessions: &[SessionMeta], cursor: Option<&str>) -> Result<usize> {
    let Some(cursor) = cursor else {
        return Ok(0);
    };

    let Some(index) = sessions.iter().position(|session| session.id == cursor) else {
        bail!("cursor '{cursor}' does not match any session id in current result set");
    };

    Ok(index + 1)
}

fn resolve_cwd_filter(all: bool, cwd: Option<&std::path::Path>) -> Result<Option<String>> {
    if all {
        return Ok(None);
    }

    let cwd = if let Some(cwd) = cwd {
        if cwd.is_absolute() {
            cwd.to_path_buf()
        } else {
            std::env::current_dir()?.join(cwd)
        }
    } else {
        std::env::current_dir()?
    };

    Ok(Some(cwd.to_string_lossy().into_owned()))
}

fn matches_search(session: &SessionMeta, needle: &str) -> bool {
    session
        .title
        .as_deref()
        .map(|title| title.to_ascii_lowercase().contains(needle))
        .unwrap_or(false)
        || session.id.to_ascii_lowercase().contains(needle)
        || session
            .cwd
            .as_deref()
            .map(|cwd| cwd.to_ascii_lowercase().contains(needle))
            .unwrap_or(false)
}

fn build_merger_summary_prompt(target: &SessionMeta, merge: &SessionMeta) -> String {
    let merge_title = merge.title.as_deref().unwrap_or("(no title)");
    let merge_cwd = merge.cwd.as_deref().unwrap_or("(unknown cwd)");
    let merge_source = merge.source.as_deref().unwrap_or("(unknown source)");
    let target_title = target.title.as_deref().unwrap_or("(no title)");

    format!(
        "You are resuming merger session {merge_id}.\n\
         \n\
         Task: build a compact context-transfer summary that will be injected into target session {target_id} ({target_title}).\n\
         \n\
         Merger session metadata:\n\
         - id: {merge_id}\n\
         - title: {merge_title}\n\
         - cwd: {merge_cwd}\n\
         - source: {merge_source}\n\
         - file_path: {merge_path}\n\
         \n\
         Requirements:\n\
         1. Produce a compact context-transfer summary from this merger session.\n\
         2. Include only non-actionable context (decisions, constraints, preferences, resolved facts).\n\
         3. Exclude pending tasks, TODO lists, or execution instructions.\n\
         4. Use this structure exactly:\n\
            - Decisions\n\
            - Constraints\n\
            - Preferences\n\
            - Resolved Facts\n\
            - Relevant Open Questions (only if still needed for context)\n\
         5. Keep it concise and transferable.\n\
         6. Do not run tools or modify files.",
        target_id = target.id,
        target_title = target_title,
        merge_id = merge.id,
        merge_title = merge_title,
        merge_cwd = merge_cwd,
        merge_source = merge_source,
        merge_path = merge.file_path.display(),
    )
}

fn build_title_generation_prompt(first_user_prompt: &str) -> String {
    [
        "You are a helpful assistant. You will be presented with a user prompt, and your job is to provide a short title for a task that will be created from that prompt.",
        "The tasks typically have to do with coding-related tasks, for example requests for bug fixes or questions about a codebase. The title you generate will be shown in the UI to represent the prompt.",
        "Generate a concise UI title (18-36 characters) for this task.",
        "Return only the title. No quotes or trailing punctuation.",
        "Do not use markdown or formatting characters.",
        "If the task includes a ticket reference (e.g. ABC-123), include it verbatim.",
        "",
        "Generate a clear, informative task title based solely on the prompt provided. Follow the rules below to ensure consistency, readability, and usefulness.",
        "",
        "How to write a good title:",
        "Generate a single-line title that captures the question or core change requested. The title should be easy to scan and useful in changelogs or review queues.",
        "- Use an imperative verb first: \"Add\", \"Fix\", \"Update\", \"Refactor\", \"Remove\", \"Locate\", \"Find\", etc.",
        "- Aim for 18-36 characters; keep under 5 words where possible.",
        "- Capitalize only the first word (unless locale requires otherwise).",
        "- Write the title in the user's locale.",
        "- Do not use punctuation at the end.",
        "- Output the title as plain text with no surrounding quotes or backticks.",
        "- Use precise, non-redundant language.",
        "- Translate fixed phrases into the user's locale (e.g., \"Fix bug\" -> \"Corrige el error\" in Spanish-ES), but leave code terms in English unless a widely adopted translation exists.",
        "- If the user provides a title explicitly, reuse it (translated if needed) and skip generation logic.",
        "- Make it clear when the user is requesting changes (use verbs like \"Fix\", \"Add\", etc) vs asking a question (use verbs like \"Find\", \"Locate\", \"Count\").",
        "- Do NOT respond to the user, answer questions, or attempt to solve the problem; just write a title that can represent the user's query.",
        "",
        "Examples:",
        "- User: \"Can we add dark-mode support to the settings page?\" -> Add dark-mode support",
        "- User: \"Fehlerbehebung: Beim Anmelden erscheint 500.\" (de-DE) -> Login-Fehler 500 beheben",
        "- User: \"Refactoriser le composant sidebar pour réduire le code dupliqué.\" (fr-FR) -> Refactoriser composant sidebar",
        "- User: \"How do I fix our login bug?\" -> Troubleshoot login bug",
        "- User: \"Where in the codebase is foo_bar created\" -> Locate foo_bar",
        "- User: \"what's 2+2\" -> Calculate 2+2",
        "",
        "By following these conventions, your titles will be readable, changelog-friendly, and helpful to both users and downstream tools.",
        "",
        "User prompt:",
        first_user_prompt,
    ]
    .join("\n")
}

fn generate_session_title(target: &SessionMeta, first_user_prompt: &str) -> Result<String> {
    let input = first_user_prompt.trim();
    if input.is_empty() {
        bail!("first user prompt is empty");
    }

    let prompt = build_title_generation_prompt(&truncate_chars_exact(input, TITLE_INPUT_MAX_CHARS));

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0));
    let schema_file = std::env::temp_dir().join(format!(
        "codex-sessions-title-schema-{}-{}.json",
        std::process::id(),
        now.as_nanos()
    ));
    let output_file = std::env::temp_dir().join(format!(
        "codex-sessions-title-output-{}-{}.txt",
        std::process::id(),
        now.as_nanos()
    ));

    let schema = serde_json::json!({
        "type": "object",
        "additionalProperties": false,
        "required": ["title"],
        "properties": {
            "title": {
                "type": "string",
                "minLength": TITLE_MIN_CHARS,
                "maxLength": TITLE_MAX_CHARS
            }
        }
    });
    fs::write(&schema_file, serde_json::to_string_pretty(&schema)?)
        .with_context(|| format!("failed writing {}", schema_file.display()))?;

    let mut command = Command::new("codex");
    command
        .arg("-a")
        .arg("never")
        .arg("-s")
        .arg("read-only")
        .arg("-m")
        .arg(TITLE_MODEL)
        .arg("-c")
        .arg("model_reasoning_effort=\"low\"")
        .arg("-c")
        .arg("web_search=\"disabled\"");

    if let Some(cwd) = target.cwd.as_deref() {
        let cwd_path = std::path::Path::new(cwd);
        if cwd_path.exists() {
            command.arg("-C").arg(cwd);
        }
    }

    command
        .arg("exec")
        .arg("--ephemeral")
        .arg("--skip-git-repo-check")
        .arg("--output-schema")
        .arg(&schema_file)
        .arg("--output-last-message")
        .arg(&output_file)
        .arg(prompt);

    let output = command
        .output()
        .context("failed running codex exec for title generation")?;

    let _ = fs::remove_file(&schema_file);

    if !output.status.success() {
        let _ = fs::remove_file(&output_file);
        let stderr = String::from_utf8_lossy(&output.stderr).trim().to_string();
        let stdout = String::from_utf8_lossy(&output.stdout).trim().to_string();
        let detail = if !stderr.is_empty() {
            stderr
        } else if !stdout.is_empty() {
            stdout
        } else {
            format!("process exited with status {}", output.status)
        };
        bail!("codex title generation failed: {detail}");
    }

    let raw = fs::read_to_string(&output_file)
        .with_context(|| format!("failed reading {}", output_file.display()))?;
    let _ = fs::remove_file(&output_file);

    parse_generated_title(&raw)
        .ok_or_else(|| anyhow::anyhow!("title generation returned an invalid title"))
}

fn parse_generated_title(raw: &str) -> Option<String> {
    let trimmed = raw.trim();
    if trimmed.is_empty() {
        return None;
    }

    if let Ok(parsed) = serde_json::from_str::<serde_json::Value>(trimmed) {
        if let Some(title) = parsed.get("title").and_then(serde_json::Value::as_str) {
            return normalize_generated_title(title);
        }
    }

    normalize_generated_title(trimmed)
}

fn normalize_generated_title(raw: &str) -> Option<String> {
    let first_line = raw
        .replace("\r\n", "\n")
        .lines()
        .find(|line| !line.trim().is_empty())?
        .trim()
        .to_string();

    let without_prefix = strip_title_prefix(&first_line);
    let without_quotes =
        without_prefix.trim_matches(|c| matches!(c, '`' | '"' | '\'' | '“' | '”' | '‘' | '’'));
    let collapsed = without_quotes
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ");
    let no_trailing_punctuation = collapsed
        .trim_end_matches(|c| matches!(c, '.' | '?' | '!'))
        .trim();

    if no_trailing_punctuation.is_empty() {
        return None;
    }

    let len = no_trailing_punctuation.chars().count();
    if len < TITLE_MIN_CHARS {
        return None;
    }
    if len > TITLE_MAX_CHARS {
        let truncated: String = no_trailing_punctuation
            .chars()
            .take(TITLE_MAX_CHARS - 1)
            .collect::<String>()
            .trim_end()
            .to_string();
        return Some(format!("{truncated}…"));
    }

    Some(no_trailing_punctuation.to_string())
}

fn strip_title_prefix(value: &str) -> String {
    let trimmed = value.trim_start();

    let mut chars = trimmed.chars();
    for expected in ['t', 'i', 't', 'l', 'e'] {
        let Some(current) = chars.next() else {
            return trimmed.to_string();
        };
        if !current.eq_ignore_ascii_case(&expected) {
            return trimmed.to_string();
        }
    }

    let Some(next) = chars.next() else {
        return trimmed.to_string();
    };
    if next != ':' && !next.is_whitespace() {
        return trimmed.to_string();
    }

    let mut suffix = chars.collect::<String>();
    if next == ':' {
        suffix = suffix.trim_start().to_string();
    }

    suffix.trim_start().to_string()
}

fn truncate_chars(value: &str, max_chars: usize) -> String {
    if value.chars().count() <= max_chars {
        return value.to_string();
    }
    let truncated: String = value.chars().take(max_chars).collect();
    format!("{truncated}...")
}

fn truncate_chars_exact(value: &str, max_chars: usize) -> String {
    if value.chars().count() <= max_chars {
        return value.to_string();
    }
    value.chars().take(max_chars).collect()
}

fn build_target_apply_prompt(merge: &SessionMeta, transfer_summary: &str) -> String {
    let merge_title = merge.title.as_deref().unwrap_or("(no title)");
    let summary = truncate_chars(transfer_summary.trim(), 12000);

    format!(
        "Merge context into this target session.\n\
         \n\
         Context merger session metadata:\n\
         - merger_id: {merge_id}\n\
         - merger_title: {merge_title}\n\
         - merger_cwd: {merge_cwd}\n\
         - merger_file_path: {merge_path}\n\
         \n\
         Context transfer summary:\n\
         {summary}\n\
         \n\
         Instructions:\n\
         1. Acknowledge this merge context briefly.\n\
         2. Preserve this context for future reasoning in this target session.\n\
         3. Do not run tools or modify files.",
        merge_id = merge.id,
        merge_title = merge_title,
        merge_cwd = merge.cwd.as_deref().unwrap_or("(unknown cwd)"),
        merge_path = merge.file_path.display(),
        summary = summary,
    )
}

fn run_codex_exec_resume(target: &SessionMeta, prompt: &str) -> Result<()> {
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

fn run_codex_exec_resume_capture_last_message(
    target: &SessionMeta,
    prompt: &str,
) -> Result<String> {
    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0));
    let output_file = std::env::temp_dir().join(format!(
        "codex-sessions-merge-last-message-{}-{}.txt",
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn normalize_generated_title_matches_desktop_rules() {
        let value = normalize_generated_title("\ntitle:   Add dark-mode support.\n")
            .expect("expected title");
        assert_eq!(value, "Add dark-mode support");
    }

    #[test]
    fn normalize_generated_title_rejects_short_values() {
        assert!(normalize_generated_title("Fix bug").is_none());
    }

    #[test]
    fn normalize_generated_title_truncates_with_ellipsis() {
        let long = "Refactor feature state management for deterministic updates";
        let title = normalize_generated_title(long).expect("expected title");
        assert!(title.ends_with('…'));
        assert!(title.chars().count() <= TITLE_MAX_CHARS);
    }

    #[test]
    fn strip_title_prefix_requires_separator() {
        assert_eq!(
            strip_title_prefix("title: Add session merge"),
            "Add session merge"
        );
        assert_eq!(
            strip_title_prefix("Title Add session merge"),
            "Add session merge"
        );
        assert_eq!(strip_title_prefix("titled feature"), "titled feature");
    }

    #[test]
    fn truncate_chars_exact_keeps_hard_limit_without_suffix() {
        let value = truncate_chars_exact("abcd", 3);
        assert_eq!(value, "abc");
    }
}
