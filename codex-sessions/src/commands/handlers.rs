use crate::adapters::session_store::{SessionStore, resolve_session_by_id};
use crate::cli::{
    ArchiveArgs, AutoRemoveArgs, AutoRemoveMode, Commands, DeleteArgs, GenerateThreadTitleArgs,
    ListArgs, MergeArgs, MessageArgs, ShowArgs, TitlesArgs, UnarchiveArgs, WatchAutoRemoveArgs,
    WatchCommand,
};
use crate::services::session_service::{
    age_days, prune_sessions, to_output_entries, to_output_entry, validate_days,
};
use crate::shared::models::{
    DeleteResult, ListResult, MergeResult, MessageResult, OperationBatchResult, SessionMeta,
    SessionResultReason, SessionResultStatus, TitleResult,
};
use crate::shared::output::OutputFormat;
use anyhow::{Result, bail};
use std::collections::{HashMap, HashSet};
use std::thread;
use std::time::Duration;

use super::codex_exec::{run_codex_exec_resume, run_codex_exec_resume_capture_last_message};
use super::output::{
    emit_merge_output, emit_operation_batch_output, emit_prune_output, emit_title_output,
};
use super::prompts::{build_merger_summary_prompt, build_target_apply_prompt};
use super::selection::{
    matches_search, resolve_cursor_start, resolve_cwd_filter, resolve_delete_targets,
    resolve_targets_for_inputs, sort_sessions, sort_sessions_by_folder_then_updated,
    validate_delete_args, with_target_session,
};
use super::title_generation::generate_session_title;
use super::watcher::cmd_watch_thread_titles;

pub(crate) fn dispatch(command: Commands) -> Result<()> {
    match command {
        Commands::List(args) => cmd_list(args),
        Commands::Titles(args) => cmd_titles(args),
        Commands::GenerateThreadTitle(args) => cmd_generate_thread_title(args),
        Commands::Show(args) => cmd_show(args),
        Commands::Message(args) => cmd_message(args),
        Commands::Delete(args) => cmd_delete(args),
        Commands::Archive(args) => cmd_archive(args),
        Commands::Unarchive(args) => cmd_unarchive(args),
        Commands::Merge(args) => cmd_merge(args),
        Commands::AutoRemove(args) => cmd_auto_remove(args),
        Commands::Watch { action } => cmd_watch(action),
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
    let pinned_ids = store.load_pinned_thread_ids()?;
    let unpinned_targets: Vec<&SessionMeta> = targets
        .iter()
        .copied()
        .filter(|target| !pinned_ids.contains(&target.id))
        .collect();

    let operation = "delete";

    let mut result_by_id: HashMap<String, DeleteResult> = if args.dry_run {
        unpinned_targets
            .iter()
            .map(|target| {
                let result = DeleteResult {
                    id: target.id.clone(),
                    file_path: target.file_path.display().to_string(),
                    status: SessionResultStatus::Skipped,
                    reason: SessionResultReason::DryRun,
                    message: None,
                };
                (result.id.clone(), result)
            })
            .collect()
    } else {
        store
            .delete_sessions_hard(&unpinned_targets)?
            .into_iter()
            .map(|result| (result.id.clone(), result))
            .collect()
    };

    let mut results = Vec::with_capacity(targets.len());
    for target in targets {
        if pinned_ids.contains(&target.id) {
            results.push(build_pinned_skip_result(target));
            continue;
        }

        let Some(result) = result_by_id.remove(&target.id) else {
            results.push(DeleteResult {
                id: target.id.clone(),
                file_path: target.file_path.display().to_string(),
                status: SessionResultStatus::Failed,
                reason: SessionResultReason::Error,
                message: Some("internal error: missing result for resolved target".to_string()),
            });
            continue;
        };

        results.push(result);
    }

    let response = build_operation_batch_result(operation, args.dry_run, results);
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

    let response = build_operation_batch_result("archive", false, results);
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

    let response = build_operation_batch_result("unarchive", false, results);
    emit_operation_batch_output(response, args.json, args.plain)
}

fn build_operation_batch_result(
    operation: &str,
    dry_run: bool,
    sessions: Vec<DeleteResult>,
) -> OperationBatchResult {
    let processed = sessions.len();
    let failed = sessions
        .iter()
        .filter(|session| session.status == SessionResultStatus::Failed)
        .count();
    let succeeded = sessions
        .iter()
        .filter(|session| session.status == SessionResultStatus::Succeeded)
        .count();
    let skipped = sessions
        .iter()
        .filter(|session| session.status == SessionResultStatus::Skipped)
        .count();

    OperationBatchResult {
        operation: operation.to_string(),
        dry_run,
        processed,
        succeeded,
        failed,
        skipped,
        sessions,
    }
}

fn build_pinned_skip_result(target: &SessionMeta) -> DeleteResult {
    DeleteResult {
        id: target.id.clone(),
        file_path: target.file_path.display().to_string(),
        status: SessionResultStatus::Skipped,
        reason: SessionResultReason::Pinned,
        message: None,
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
        merged_deleted: deleted.status == SessionResultStatus::Succeeded,
        merged_file_path: deleted.file_path,
    };

    emit_merge_output(result, args.json, args.plain)
}

fn cmd_auto_remove(args: AutoRemoveArgs) -> Result<()> {
    let store = SessionStore::new(args.home)?;
    let format = OutputFormat::from_flags(args.json, args.plain);
    let hard = matches!(args.mode, AutoRemoveMode::Delete);
    let mode = if hard { "delete" } else { "archive" };
    let report = prune_sessions(&store, args.older_than_days, args.dry_run, hard, mode)?;
    emit_prune_output(&report, format)
}

fn cmd_watch(action: WatchCommand) -> Result<()> {
    match action {
        WatchCommand::AutoRemove(args) => cmd_watch_auto_remove(args),
        WatchCommand::ThreadTitles { action } => cmd_watch_thread_titles(action),
    }
}

fn cmd_watch_auto_remove(args: WatchAutoRemoveArgs) -> Result<()> {
    validate_days(args.older_than_days)?;
    if args.interval_minutes == 0 {
        bail!("--interval-minutes must be >= 1");
    }

    let store = SessionStore::new(args.home)?;
    let format = OutputFormat::from_flags(args.json, args.plain);
    let interval = Duration::from_secs(args.interval_minutes * 60);
    let hard = matches!(args.mode, AutoRemoveMode::Delete);
    let mode = if hard { "delete" } else { "archive" };

    loop {
        let report = prune_sessions(&store, args.older_than_days, args.dry_run, hard, mode)?;
        emit_prune_output(&report, format)?;

        if args.once {
            break;
        }

        if !args.json && !args.plain {
            println!(
                "Waiting {} minute(s) before next auto-remove...",
                args.interval_minutes
            );
        }

        thread::sleep(interval);
    }

    Ok(())
}
