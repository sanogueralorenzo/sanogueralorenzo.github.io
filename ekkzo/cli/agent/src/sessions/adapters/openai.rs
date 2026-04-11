use super::{SessionsAdapter, required_string_at_path, required_string_or_number};
use crate::sessions::contracts::{SessionContractRecord, SessionProvider};
use serde_json::{Value, json};
use std::collections::HashMap;
use std::env;
use std::fs::{self, File};
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

pub struct OpenAiSessionsAdapter;

const SESSIONS_SUBDIR: &str = "sessions";
const SESSION_INDEX_FILE: &str = "session_index.jsonl";

impl SessionsAdapter for OpenAiSessionsAdapter {
    fn map_session(&self, value: &Value) -> Result<SessionContractRecord, String> {
        let id = required_string_at_path(value, &["thread", "id"])
            .or_else(|_| required_string_at_path(value, &["id"]))?;
        let name = required_string_at_path(value, &["thread", "name"])
            .or_else(|_| required_string_at_path(value, &["name"]))?;
        let cwd = required_string_at_path(value, &["thread", "cwd"])
            .or_else(|_| required_string_at_path(value, &["cwd"]))?;

        let updated_at = value
            .get("thread")
            .and_then(|thread| required_string_or_number(thread, "updatedAt").ok())
            .or_else(|| required_string_or_number(value, "updatedAt").ok())
            .ok_or_else(|| "missing required field 'updatedAt'".to_string())?;

        Ok(SessionContractRecord {
            provider: SessionProvider::OpenAi,
            id,
            name,
            cwd,
            updated_at,
        })
    }
}

#[derive(Default, Clone)]
struct SessionFileMetadata {
    cwd: String,
    updated_at: String,
}

pub fn resume_command(id: &str) -> Vec<String> {
    vec!["codex".to_string(), "resume".to_string(), id.to_string()]
}

fn openai_config_root() -> Result<PathBuf, String> {
    let home = env::var("HOME").map_err(|_| "HOME is not set".to_string())?;
    Ok(PathBuf::from(home).join(".codex"))
}

pub(crate) fn list_local_sessions_at_root(
    root_override: Option<&Path>,
) -> Result<Vec<SessionContractRecord>, String> {
    let root = match root_override {
        Some(value) => value.to_path_buf(),
        None => openai_config_root()?,
    };
    list_local_sessions_in_root(&root)
}

fn list_local_sessions_in_root(root: &Path) -> Result<Vec<SessionContractRecord>, String> {
    let session_file_metadata = collect_session_file_metadata(root)?;
    let mut sessions_by_id: HashMap<String, SessionContractRecord> = HashMap::new();

    for index_entry in read_index_entries(root)? {
        let Some(id) = index_entry.get("id").and_then(Value::as_str) else {
            continue;
        };

        let name = index_entry
            .get("title")
            .and_then(Value::as_str)
            .or_else(|| index_entry.get("thread_name").and_then(Value::as_str))
            .unwrap_or(id)
            .to_string();

        let metadata = session_file_metadata.get(id).cloned().unwrap_or_default();
        let cwd = index_entry
            .get("cwd")
            .and_then(Value::as_str)
            .unwrap_or(metadata.cwd.as_str())
            .to_string();

        let updated_at = index_entry
            .get("updated_at")
            .and_then(Value::as_str)
            .unwrap_or(metadata.updated_at.as_str())
            .to_string();

        let mapped = OpenAiSessionsAdapter.map_session(&json!({
            "id": id,
            "name": name,
            "cwd": cwd,
            "updatedAt": if updated_at.is_empty() { "0".to_string() } else { updated_at },
        }))?;
        sessions_by_id.insert(mapped.id.clone(), mapped);
    }

    for (id, metadata) in session_file_metadata {
        if sessions_by_id.contains_key(&id) {
            continue;
        }

        let mapped = OpenAiSessionsAdapter.map_session(&json!({
            "id": id,
            "name": id,
            "cwd": metadata.cwd,
            "updatedAt": if metadata.updated_at.is_empty() { "0".to_string() } else { metadata.updated_at },
        }))?;
        sessions_by_id.insert(mapped.id.clone(), mapped);
    }

    let mut sessions = sessions_by_id.into_values().collect::<Vec<_>>();
    sessions.sort_by(|left, right| {
        right
            .updated_at
            .cmp(&left.updated_at)
            .then_with(|| left.id.cmp(&right.id))
    });
    Ok(sessions)
}

pub(crate) fn delete_local_session_at_root(
    id: &str,
    root_override: Option<&Path>,
) -> Result<usize, String> {
    let root = match root_override {
        Some(value) => value.to_path_buf(),
        None => openai_config_root()?,
    };
    delete_local_session_in_root(&root, id)
}

fn delete_local_session_in_root(root: &Path, id: &str) -> Result<usize, String> {
    let mut deleted = 0;
    deleted += remove_index_entry(root, id)?;
    deleted += remove_session_files(root, Some(id))?;
    Ok(deleted)
}

pub(crate) fn delete_all_local_sessions_at_root(
    root_override: Option<&Path>,
) -> Result<usize, String> {
    let root = match root_override {
        Some(value) => value.to_path_buf(),
        None => openai_config_root()?,
    };
    delete_all_local_sessions_in_root(&root)
}

fn delete_all_local_sessions_in_root(root: &Path) -> Result<usize, String> {
    let mut deleted = 0;
    deleted += clear_index_file(root)?;
    deleted += remove_session_files(root, None)?;
    Ok(deleted)
}

fn read_index_entries(root: &Path) -> Result<Vec<Value>, String> {
    let index_path = root.join(SESSION_INDEX_FILE);
    if !index_path.exists() {
        return Ok(Vec::new());
    }

    let file = File::open(&index_path)
        .map_err(|err| format!("failed to open {}: {err}", index_path.display()))?;
    let reader = BufReader::new(file);
    let mut entries = Vec::new();

    for line in reader.lines() {
        let line = line.map_err(|err| format!("failed to read {}: {err}", index_path.display()))?;
        if line.trim().is_empty() {
            continue;
        }
        if let Ok(value) = serde_json::from_str::<Value>(&line) {
            entries.push(value);
        }
    }

    Ok(entries)
}

fn remove_index_entry(root: &Path, id: &str) -> Result<usize, String> {
    let index_path = root.join(SESSION_INDEX_FILE);
    if !index_path.exists() {
        return Ok(0);
    }

    let file = File::open(&index_path)
        .map_err(|err| format!("failed to open {}: {err}", index_path.display()))?;
    let reader = BufReader::new(file);
    let mut retained = Vec::new();
    let mut removed = 0usize;

    for line in reader.lines() {
        let line = line.map_err(|err| format!("failed to read {}: {err}", index_path.display()))?;
        if line.trim().is_empty() {
            continue;
        }

        let should_keep = match serde_json::from_str::<Value>(&line) {
            Ok(value) => {
                let entry_id = value.get("id").and_then(Value::as_str);
                if entry_id == Some(id) {
                    removed += 1;
                    false
                } else {
                    true
                }
            }
            Err(_) => true,
        };

        if should_keep {
            retained.push(line);
        }
    }

    let replacement = if retained.is_empty() {
        String::new()
    } else {
        format!("{}\n", retained.join("\n"))
    };

    fs::write(&index_path, replacement)
        .map_err(|err| format!("failed to write {}: {err}", index_path.display()))?;
    Ok(removed)
}

fn clear_index_file(root: &Path) -> Result<usize, String> {
    let index_path = root.join(SESSION_INDEX_FILE);
    if !index_path.exists() {
        return Ok(0);
    }

    let entries = read_index_entries(root)?;
    fs::write(&index_path, "")
        .map_err(|err| format!("failed to clear {}: {err}", index_path.display()))?;
    Ok(entries.len())
}

fn collect_session_file_metadata(root: &Path) -> Result<HashMap<String, SessionFileMetadata>, String> {
    let mut metadata_by_id = HashMap::new();
    let sessions_root = root.join(SESSIONS_SUBDIR);
    let mut files = Vec::new();
    collect_files_recursively(&sessions_root, &mut files)?;

    for file_path in files {
        if !is_rollout_session_file(&file_path) {
            continue;
        }

        if let Some((id, metadata)) = read_rollout_session_metadata(&file_path)? {
            metadata_by_id.insert(id, metadata);
        }
    }

    Ok(metadata_by_id)
}

fn remove_session_files(root: &Path, id_filter: Option<&str>) -> Result<usize, String> {
    let sessions_root = root.join(SESSIONS_SUBDIR);
    let mut files = Vec::new();
    collect_files_recursively(&sessions_root, &mut files)?;

    let mut removed = 0usize;
    for file_path in files {
        if !is_rollout_session_file(&file_path) {
            continue;
        }

        let Some((id, _)) = read_rollout_session_metadata(&file_path)? else {
            continue;
        };

        if id_filter.is_some() && Some(id.as_str()) != id_filter {
            continue;
        }

        fs::remove_file(&file_path)
            .map_err(|err| format!("failed to delete {}: {err}", file_path.display()))?;
        removed += 1;
    }

    Ok(removed)
}

fn read_rollout_session_metadata(
    file_path: &Path,
) -> Result<Option<(String, SessionFileMetadata)>, String> {
    let file =
        File::open(file_path).map_err(|err| format!("failed to open {}: {err}", file_path.display()))?;
    let mut reader = BufReader::new(file);
    let mut first_line = String::new();
    let bytes_read = reader
        .read_line(&mut first_line)
        .map_err(|err| format!("failed to read {}: {err}", file_path.display()))?;
    if bytes_read == 0 {
        return Ok(None);
    }

    let value: Value = match serde_json::from_str(first_line.trim()) {
        Ok(value) => value,
        Err(_) => return Ok(None),
    };

    let Some(id) = value
        .get("payload")
        .and_then(|payload| payload.get("id"))
        .and_then(Value::as_str)
        .map(ToString::to_string)
    else {
        return Ok(None);
    };

    let cwd = value
        .get("payload")
        .and_then(|payload| payload.get("cwd"))
        .and_then(Value::as_str)
        .unwrap_or("")
        .to_string();

    let updated_at = value
        .get("payload")
        .and_then(|payload| payload.get("timestamp"))
        .and_then(Value::as_str)
        .map(ToString::to_string)
        .unwrap_or_else(|| file_mtime_epoch_seconds(file_path).unwrap_or_else(|| "0".to_string()));

    Ok(Some((id, SessionFileMetadata { cwd, updated_at })))
}

fn collect_files_recursively(root: &Path, files: &mut Vec<PathBuf>) -> Result<(), String> {
    if !root.exists() {
        return Ok(());
    }

    for entry in
        fs::read_dir(root).map_err(|err| format!("failed to read {}: {err}", root.display()))?
    {
        let entry = entry.map_err(|err| format!("failed to read entry in {}: {err}", root.display()))?;
        let path = entry.path();
        let file_type = entry
            .file_type()
            .map_err(|err| format!("failed to inspect {}: {err}", path.display()))?;
        if file_type.is_dir() {
            collect_files_recursively(&path, files)?;
        } else if file_type.is_file() {
            files.push(path);
        }
    }

    Ok(())
}

fn is_rollout_session_file(path: &Path) -> bool {
    let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
        return false;
    };
    name.starts_with("rollout-") && name.ends_with(".jsonl")
}

fn file_mtime_epoch_seconds(path: &Path) -> Option<String> {
    let metadata = fs::metadata(path).ok()?;
    let modified = metadata.modified().ok()?;
    let duration = modified.duration_since(UNIX_EPOCH).ok()?;
    Some(duration.as_secs().to_string())
}

#[cfg(test)]
mod tests {
    use super::{
        OpenAiSessionsAdapter, SessionsAdapter, delete_all_local_sessions_in_root,
        delete_local_session_in_root, list_local_sessions_in_root,
    };
    use crate::sessions::contracts::SessionProvider;
    use serde_json::json;
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn maps_nested_thread_shape() {
        let adapter = OpenAiSessionsAdapter;
        let value = json!({
            "thread": {
                "id": "thread_123",
                "name": "Fix auth",
                "cwd": "/repo",
                "updatedAt": "2026-04-11T12:00:00Z"
            }
        });

        let mapped = adapter.map_session(&value).expect("session should map");
        assert_eq!(mapped.provider, SessionProvider::OpenAi);
        assert_eq!(mapped.id, "thread_123");
        assert_eq!(mapped.name, "Fix auth");
        assert_eq!(mapped.cwd, "/repo");
        assert_eq!(mapped.updated_at, "2026-04-11T12:00:00Z");
    }

    #[test]
    fn maps_flat_shape_fallback() {
        let adapter = OpenAiSessionsAdapter;
        let value = json!({
            "id": "thread_456",
            "name": "Review",
            "cwd": "/workspace",
            "updatedAt": 1712836800
        });

        let mapped = adapter.map_session(&value).expect("session should map");
        assert_eq!(mapped.id, "thread_456");
        assert_eq!(mapped.updated_at, "1712836800");
    }

    #[test]
    fn rejects_missing_required_fields() {
        let adapter = OpenAiSessionsAdapter;
        let err = adapter
            .map_session(&json!({ "thread": { "id": "thread_789" } }))
            .expect_err("mapping should fail");
        assert!(err.contains("missing required field"));
    }

    #[test]
    fn list_and_delete_use_local_store_layout() {
        let root = create_temp_dir();
        let sessions_day = root.join(".codex").join("sessions").join("2026").join("04").join("11");
        fs::create_dir_all(&sessions_day).expect("session directory should be created");

        let index_path = root.join(".codex").join("session_index.jsonl");
        fs::write(
            &index_path,
            r#"{"id":"s1","title":"One","updated_at":"2026-04-11T00:00:00Z"}
{"id":"s2","title":"Two","updated_at":"2026-04-11T01:00:00Z"}
"#,
        )
        .expect("index file should be written");

        fs::write(
            sessions_day.join("rollout-2026-04-11T00-00-00-s1.jsonl"),
            r#"{"type":"session_meta","payload":{"id":"s1","cwd":"/repo-one","timestamp":"2026-04-11T00:00:00Z"}}"#,
        )
        .expect("session s1 should be written");
        fs::write(
            sessions_day.join("rollout-2026-04-11T01-00-00-s2.jsonl"),
            r#"{"type":"session_meta","payload":{"id":"s2","cwd":"/repo-two","timestamp":"2026-04-11T01:00:00Z"}}"#,
        )
        .expect("session s2 should be written");

        let list_root = root.join(".codex");
        let sessions = list_local_sessions_in_root(&list_root).expect("sessions should list");
        assert_eq!(sessions.len(), 2);
        assert_eq!(sessions[0].id, "s2");
        assert_eq!(sessions[0].cwd, "/repo-two");
        assert_eq!(sessions[1].id, "s1");

        let deleted = delete_local_session_in_root(&list_root, "s1").expect("delete should work");
        assert!(deleted >= 1);
        let sessions_after_delete =
            list_local_sessions_in_root(&list_root).expect("sessions should list after delete");
        assert_eq!(sessions_after_delete.len(), 1);
        assert_eq!(sessions_after_delete[0].id, "s2");

        let deleted_all =
            delete_all_local_sessions_in_root(&list_root).expect("delete all should work");
        assert!(deleted_all >= 1);
        let sessions_after_delete_all =
            list_local_sessions_in_root(&list_root).expect("sessions should list after delete all");
        assert!(sessions_after_delete_all.is_empty());
    }

    fn create_temp_dir() -> PathBuf {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("time should be valid")
            .as_nanos();
        let path = std::env::temp_dir().join(format!("agent-openai-sessions-test-{suffix}"));
        fs::create_dir_all(&path).expect("temp directory should be created");
        path
    }
}
