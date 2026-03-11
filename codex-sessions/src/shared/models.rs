use chrono::{DateTime, Utc};
use serde::Serialize;
use std::path::PathBuf;

#[derive(Debug, Serialize, Clone)]
pub struct SessionEntry {
    pub id: String,
    pub title: Option<String>,
    pub folder: String,
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

#[derive(Debug, Serialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SessionResultStatus {
    Succeeded,
    Skipped,
    Failed,
}

#[derive(Debug, Serialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum SessionResultReason {
    Completed,
    DryRun,
    Pinned,
    Error,
}

#[derive(Debug, Serialize)]
pub struct DeleteResult {
    pub id: String,
    pub file_path: String,
    pub status: SessionResultStatus,
    pub reason: SessionResultReason,
    pub message: Option<String>,
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
pub struct OperationBatchResult {
    pub operation: String,
    pub dry_run: bool,
    pub hard: bool,
    pub processed: usize,
    pub succeeded: usize,
    pub failed: usize,
    pub skipped: usize,
    pub sessions: Vec<DeleteResult>,
}

#[derive(Debug, Serialize)]
pub struct MessageResult {
    pub id: String,
    pub message: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct MergeResult {
    pub target_id: String,
    pub merged_id: String,
    pub merged_deleted: bool,
    pub merged_file_path: String,
}

#[derive(Debug, Serialize)]
pub struct TitleResult {
    pub id: String,
    pub title: String,
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
