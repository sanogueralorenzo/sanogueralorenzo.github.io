use chrono::{DateTime, Utc};
use serde::Serialize;
use std::path::PathBuf;

#[derive(Debug, Serialize, Clone)]
pub struct SessionEntry {
    pub id: String,
    pub title: Option<String>,
    pub file_path: String,
    pub relative_path: String,
    pub cwd: Option<String>,
    pub source: Option<String>,
    pub source_kind: String,
    pub archived: bool,
    pub created_at: String,
    pub last_updated_at: String,
    pub age_days: i64,
    pub size_bytes: u64,
}

#[derive(Debug, Serialize)]
pub struct ListResult {
    pub data: Vec<SessionEntry>,
    pub next_cursor: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct DeleteResult {
    pub deleted: bool,
    pub id: String,
    pub file_path: String,
    pub action: String,
}

#[derive(Debug, Serialize)]
pub struct PruneResult {
    pub dry_run: bool,
    pub hard: bool,
    pub older_than_days: i64,
    pub scanned: usize,
    pub pruned: usize,
    pub sessions: Vec<DeleteResult>,
}

#[derive(Debug, Serialize)]
pub struct MessageResult {
    pub id: String,
    pub message: Option<String>,
}

#[derive(Debug, Clone)]
pub struct SessionMeta {
    pub id: String,
    pub title: Option<String>,
    pub file_path: PathBuf,
    pub relative_path: String,
    pub cwd: Option<String>,
    pub source: Option<String>,
    pub source_kind: String,
    pub archived: bool,
    pub created_at: DateTime<Utc>,
    pub last_updated_at: DateTime<Utc>,
    pub size_bytes: u64,
}
