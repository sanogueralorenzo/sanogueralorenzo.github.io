use crate::sessions::adapters::session_store::SessionStore;
use crate::sessions::shared::models::{
    DeleteResult, PruneResult, SessionEntry, SessionMeta, SessionResultReason, SessionResultStatus,
};
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
    mode: &str,
) -> Result<PruneResult> {
    validate_days(older_than_days)?;

    let sessions = store.collect_sessions()?;
    let pinned_ids = store.load_pinned_thread_ids()?;
    let mut to_prune: Vec<&SessionMeta> = sessions
        .iter()
        .filter(|session| {
            !session.archived
                && !pinned_ids.contains(&session.id)
                && age_days(session.last_updated_at) >= older_than_days
        })
        .collect();
    to_prune.sort_by(|a, b| a.last_updated_at.cmp(&b.last_updated_at));

    let mut deleted = Vec::with_capacity(to_prune.len());

    if dry_run {
        for session in to_prune {
            deleted.push(DeleteResult {
                id: session.id.clone(),
                file_path: session.file_path.display().to_string(),
                status: SessionResultStatus::Skipped,
                reason: SessionResultReason::DryRun,
                message: None,
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
        mode: mode.to_string(),
        older_than_days,
        scanned: sessions.iter().filter(|session| !session.archived).count(),
        pruned: deleted
            .iter()
            .filter(|session| session.status == SessionResultStatus::Succeeded)
            .count(),
        sessions: deleted,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use uuid::Uuid;

    #[test]
    fn prune_sessions_excludes_pinned_threads() {
        let temp_root = std::env::temp_dir().join(format!("codex-core-test-{}", Uuid::new_v4()));
        let codex_home = temp_root.join(".codex");
        let sessions_dir = codex_home
            .join("sessions")
            .join("2020")
            .join("01")
            .join("01");
        fs::create_dir_all(&sessions_dir).expect("create sessions dir");

        let pinned_id = "019cc5d1-ec61-7c90-a7d8-2524f8828fd9";
        let unpinned_id = "019cc5d1-ec61-7c90-a7d8-2524f8828fda";

        let pinned_file =
            sessions_dir.join(format!("rollout-2020-01-01T00-00-00-{pinned_id}.jsonl"));
        let unpinned_file =
            sessions_dir.join(format!("rollout-2020-01-01T00-00-01-{unpinned_id}.jsonl"));

        let old_session_line = "{\"type\":\"session_meta\",\"payload\":{\"cwd\":\"/tmp\",\"source\":\"cli\"},\"timestamp\":\"2020-01-01T00:00:00Z\"}\n";
        fs::write(&pinned_file, old_session_line).expect("write pinned session");
        fs::write(&unpinned_file, old_session_line).expect("write unpinned session");

        let global_state_path = codex_home.join(".codex-global-state.json");
        fs::write(
            &global_state_path,
            format!("{{\"pinned-thread-ids\":[\"{pinned_id}\"]}}\n"),
        )
        .expect("write global state");

        let store = SessionStore::new(Some(codex_home)).expect("create store");
        let report = prune_sessions(&store, 1, true, true, "delete").expect("prune sessions");

        assert_eq!(report.scanned, 2);
        assert_eq!(report.pruned, 0);
        assert_eq!(report.sessions.len(), 1);
        assert_eq!(report.sessions[0].id, unpinned_id);

        let _ = fs::remove_dir_all(temp_root);
    }
}
