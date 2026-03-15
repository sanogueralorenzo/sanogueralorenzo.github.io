use crate::sessions::adapters::session_store::{SessionStore, resolve_session_by_id};
use crate::sessions::cli::{DeleteArgs, SortBy};
use crate::sessions::services::session_service::{age_days, validate_days};
use crate::sessions::shared::models::SessionMeta;
use anyhow::{Result, bail};
use std::collections::HashSet;

pub(crate) fn with_target_session<T, F>(store: &SessionStore, id: &str, action: F) -> Result<T>
where
    F: FnOnce(&SessionMeta) -> Result<T>,
{
    let sessions = store.collect_sessions()?;
    let target = resolve_session_by_id(&sessions, id)?;
    action(target)
}

pub(crate) fn validate_delete_args(args: &DeleteArgs) -> Result<()> {
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

pub(crate) fn has_selector_flags(args: &DeleteArgs) -> bool {
    args.all
        || args.older_than_days.is_some()
        || has_non_empty_value(args.folder.as_deref())
        || has_non_empty_value(args.search.as_deref())
}

pub(crate) fn resolve_delete_targets<'a>(
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
        if let Some(days) = args.older_than_days
            && age_days(session.last_updated_at) < days
        {
            continue;
        }
        if let Some(folder) = folder_filter.as_deref() {
            let session_folder = session_folder_key(session.cwd.as_deref());
            if session_folder != folder {
                continue;
            }
        }
        if let Some(needle) = search_filter.as_deref()
            && !matches_search(session, needle)
        {
            continue;
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

pub(crate) fn resolve_targets_for_inputs<'a>(
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

pub(crate) fn sort_sessions(sessions: &mut [SessionMeta], sort_by: SortBy) {
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

pub(crate) fn sort_sessions_by_folder_then_updated(sessions: &mut [SessionMeta]) {
    sessions.sort_by(|a, b| {
        let a_folder = session_folder_key(a.cwd.as_deref());
        let b_folder = session_folder_key(b.cwd.as_deref());
        a_folder
            .cmp(&b_folder)
            .then_with(|| b.last_updated_at.cmp(&a.last_updated_at))
            .then_with(|| b.id.cmp(&a.id))
    });
}

pub(crate) fn session_folder_key(cwd: Option<&str>) -> String {
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

pub(crate) fn resolve_cursor_start(
    sessions: &[SessionMeta],
    cursor: Option<&str>,
) -> Result<usize> {
    let Some(cursor) = cursor else {
        return Ok(0);
    };

    let Some(index) = sessions.iter().position(|session| session.id == cursor) else {
        bail!("cursor '{cursor}' does not match any session id in current result set");
    };

    Ok(index + 1)
}

pub(crate) fn resolve_cwd_filter(
    all: bool,
    cwd: Option<&std::path::Path>,
) -> Result<Option<String>> {
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

pub(crate) fn matches_search(session: &SessionMeta, needle: &str) -> bool {
    contains_normalized_needle(session.title.as_deref(), needle)
        || session.id.to_ascii_lowercase().contains(needle)
        || contains_normalized_needle(session.cwd.as_deref(), needle)
}

fn has_non_empty_value(value: Option<&str>) -> bool {
    value.map(str::trim).is_some_and(|v| !v.is_empty())
}

fn contains_normalized_needle(value: Option<&str>, needle: &str) -> bool {
    value
        .map(|v| v.to_ascii_lowercase().contains(needle))
        .unwrap_or(false)
}
