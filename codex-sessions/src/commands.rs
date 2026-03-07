use crate::adapters::session_store::{SessionStore, resolve_session_by_id};
use crate::cli::{
    ArchiveArgs, Cli, Commands, DeleteArgs, ListArgs, MessageArgs, PruneArgs, ShowArgs, SortBy,
    TitlesArgs, UnarchiveArgs, WatchArgs,
};
use crate::services::session_service::{
    age_days, prune_sessions, to_output_entries, to_output_entry, validate_days,
};
use crate::shared::models::{DeleteResult, ListResult, MessageResult, PruneResult, SessionMeta};
use crate::shared::output::OutputFormat;
use anyhow::{Result, bail};
use clap::Parser;
use std::collections::HashSet;
use std::thread;
use std::time::Duration;

pub fn run() -> Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::List(args) => cmd_list(args),
        Commands::Titles(args) => cmd_titles(args),
        Commands::Show(args) => cmd_show(args),
        Commands::Message(args) => cmd_message(args),
        Commands::Delete(args) => cmd_delete(args),
        Commands::Archive(args) => cmd_archive(args),
        Commands::Unarchive(args) => cmd_unarchive(args),
        Commands::Prune(args) => cmd_prune(args),
        Commands::Watch(args) => cmd_watch(args),
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

    sort_sessions(&mut sessions, sort_by);

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
    let titles = store.load_titles()?;

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
    let store = SessionStore::new(args.home)?;
    let result = with_target_session(&store, &args.id, |target| {
        if args.hard {
            store.delete_session_hard(target)
        } else {
            store.archive_session(target)
        }
    })?;

    emit_delete_output(result, args.json, args.plain)
}

fn cmd_archive(args: ArchiveArgs) -> Result<()> {
    let store = SessionStore::new(args.home)?;
    let result = with_target_session(&store, &args.id, |target| store.archive_session(target))?;
    emit_delete_output(result, args.json, args.plain)
}

fn cmd_unarchive(args: UnarchiveArgs) -> Result<()> {
    let store = SessionStore::new(args.home)?;
    let result = with_target_session(&store, &args.id, |target| store.unarchive_session(target))?;
    emit_delete_output(result, args.json, args.plain)
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

fn emit_delete_output(result: DeleteResult, json: bool, plain: bool) -> Result<()> {
    if json {
        println!("{}", serde_json::to_string_pretty(&result)?);
    } else if plain {
        println!("{}\t{}\t{}", result.id, result.action, result.file_path);
    } else {
        match result.action.as_str() {
            "archived" => println!("Archived session {}", result.id),
            "unarchived" => println!("Unarchived session {}", result.id),
            _ => println!("Deleted session {}", result.id),
        }
        println!("Path: {}", result.file_path);
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
                println!("{}\t{}\t{}", session.id, session.action, session.file_path);
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
                println!(
                    "- {} [{}] ({})",
                    session.id, session.action, session.file_path
                );
            }
        }
    }

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
