use crate::adapters::session_store::SessionStore;
use crate::shared::models::{DeleteResult, PruneResult, SessionEntry, SessionMeta};
use anyhow::{Result, bail};
use chrono::{DateTime, Utc};
use std::path::Path;

pub fn validate_days(days: i64) -> Result<()> {
    if days < 0 {
        bail!("days must be >= 0");
    }
    Ok(())
}

pub fn age_days(last_updated_at: DateTime<Utc>) -> i64 {
    let duration = Utc::now() - last_updated_at;
    if duration.num_days() < 0 {
        0
    } else {
        duration.num_days()
    }
}

pub fn to_output_entries(sessions: &[SessionMeta]) -> Vec<SessionEntry> {
    sessions.iter().map(to_output_entry).collect()
}

pub fn to_output_entry(session: &SessionMeta) -> SessionEntry {
    SessionEntry {
        id: session.id.clone(),
        title: session.title.clone(),
        folder: folder_from_cwd(session.cwd.as_deref()),
        file_path: session.file_path.display().to_string(),
        relative_path: session.relative_path.clone(),
        cwd: session.cwd.clone(),
        source: session.source.clone(),
        source_kind: session.source_kind.clone(),
        archived: session.archived,
        created_at: session.created_at.to_rfc3339(),
        last_updated_at: session.last_updated_at.to_rfc3339(),
        age_days: age_days(session.last_updated_at),
        size_bytes: session.size_bytes,
    }
}

fn folder_from_cwd(cwd: Option<&str>) -> String {
    let Some(cwd) = cwd else {
        return "unknown".to_string();
    };
    let trimmed = cwd.trim();
    if trimmed.is_empty() {
        return "unknown".to_string();
    }

    let path = Path::new(trimmed);
    path.file_name()
        .and_then(|value| value.to_str())
        .map(|value| value.trim())
        .filter(|value| !value.is_empty())
        .unwrap_or(trimmed)
        .to_string()
}

pub fn prune_sessions(
    store: &SessionStore,
    older_than_days: i64,
    dry_run: bool,
    hard: bool,
) -> Result<PruneResult> {
    validate_days(older_than_days)?;

    let sessions = store.collect_sessions()?;
    let mut to_prune: Vec<&SessionMeta> = sessions
        .iter()
        .filter(|session| !session.archived && age_days(session.last_updated_at) >= older_than_days)
        .collect();
    to_prune.sort_by(|a, b| a.last_updated_at.cmp(&b.last_updated_at));

    let mut deleted = Vec::with_capacity(to_prune.len());

    if dry_run {
        for session in to_prune {
            deleted.push(DeleteResult {
                deleted: false,
                id: session.id.clone(),
                file_path: session.file_path.display().to_string(),
                action: if hard {
                    "deleted".to_string()
                } else {
                    "archived".to_string()
                },
            });
        }
    } else if hard {
        deleted = store.delete_sessions_hard(&to_prune)?;
    } else {
        for session in to_prune {
            let result = store.archive_session(session)?;
            deleted.push(result);
        }
    }

    Ok(PruneResult {
        dry_run,
        hard,
        older_than_days,
        scanned: sessions.iter().filter(|session| !session.archived).count(),
        pruned: deleted.len(),
        sessions: deleted,
    })
}
