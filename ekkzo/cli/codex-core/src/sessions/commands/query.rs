use crate::sessions::adapters::session_store::{SessionStore, resolve_session_by_id};
use crate::sessions::cli::{GenerateThreadTitleArgs, ListArgs, MessageArgs, ShowArgs, TitlesArgs};
use crate::sessions::services::session_service::{
    age_days, to_output_entries, to_output_entry, validate_days,
};
use crate::sessions::shared::models::{ListResult, MessageResult};
use anyhow::{Result, bail};
use std::collections::HashSet;

use super::output::emit_title_output;
use super::selection::{
    matches_search, resolve_cursor_start, resolve_cwd_filter, sort_sessions, with_target_session,
};
use super::title_generation::generate_session_title;

pub(crate) fn cmd_list(args: ListArgs) -> Result<()> {
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

    let response = ListResult {
        data: to_output_entries(&page),
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

pub(crate) fn cmd_titles(args: TitlesArgs) -> Result<()> {
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

pub(crate) fn cmd_generate_thread_title(args: GenerateThreadTitleArgs) -> Result<()> {
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

    emit_title_output(
        crate::sessions::shared::models::TitleResult {
            id: target.id.clone(),
            title,
        },
        args.json,
        args.plain,
    )
}

pub(crate) fn cmd_show(args: ShowArgs) -> Result<()> {
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

pub(crate) fn cmd_message(args: MessageArgs) -> Result<()> {
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
