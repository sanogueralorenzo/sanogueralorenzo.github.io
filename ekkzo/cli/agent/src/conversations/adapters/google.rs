use super::{SessionsAdapter, required_string, required_string_or_number};
use crate::conversations::contracts::{SessionContractRecord, SessionProvider};
use serde_json::{Value, json};
use std::env;
use std::fs::{self, File};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

pub struct GoogleSessionsAdapter;

const TMP_SUBDIR: &str = "tmp";

impl SessionsAdapter for GoogleSessionsAdapter {
    fn map_session(&self, value: &Value) -> Result<SessionContractRecord, String> {
        Ok(SessionContractRecord {
            provider: SessionProvider::Google,
            id: required_string(value, "sessionId")?,
            name: required_string(value, "title")?,
            cwd: required_string(value, "cwd")?,
            updated_at: required_string_or_number(value, "updatedAt")?,
        })
    }
}

pub fn resume_command(id: &str) -> Vec<String> {
    vec!["gemini".to_string(), "--resume".to_string(), id.to_string()]
}

fn google_tmp_root() -> Result<PathBuf, String> {
    let home = env::var("HOME").map_err(|_| "HOME is not set".to_string())?;
    Ok(PathBuf::from(home).join(".gemini").join(TMP_SUBDIR))
}

pub(crate) fn list_local_sessions_at_root(
    root_override: Option<&Path>,
) -> Result<Vec<SessionContractRecord>, String> {
    let root = match root_override {
        Some(value) => value.to_path_buf(),
        None => google_tmp_root()?,
    };
    list_local_sessions_in_root(&root)
}

fn list_local_sessions_in_root(tmp_root: &Path) -> Result<Vec<SessionContractRecord>, String> {
    let mut files = Vec::new();
    collect_files_recursively(tmp_root, &mut files)?;
    let mut sessions = Vec::new();

    for file_path in files {
        if !is_google_session_file(&file_path) {
            continue;
        }

        let value = read_json_file(&file_path)?;
        let Some(session_id) = value
            .get("sessionId")
            .and_then(Value::as_str)
            .map(ToString::to_string)
        else {
            continue;
        };

        let title = value
            .get("title")
            .and_then(Value::as_str)
            .map(ToString::to_string)
            .or_else(|| {
                value
                    .get("messages")
                    .and_then(Value::as_array)
                    .and_then(|messages| {
                        messages.iter().find_map(|message| {
                            if message.get("type").and_then(Value::as_str) != Some("user") {
                                return None;
                            }

                            message
                                .get("content")
                                .and_then(Value::as_array)
                                .and_then(|content| content.first())
                                .and_then(|first| first.get("text"))
                                .and_then(Value::as_str)
                                .map(ToString::to_string)
                        })
                    })
            })
            .unwrap_or_else(|| session_id.clone());

        let cwd = value
            .get("cwd")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();

        let updated_at = value
            .get("updatedAt")
            .and_then(Value::as_str)
            .or_else(|| value.get("lastUpdated").and_then(Value::as_str))
            .map(ToString::to_string)
            .unwrap_or_else(|| file_mtime_epoch_seconds(&file_path).unwrap_or_else(|| "0".to_string()));

        let mapped = GoogleSessionsAdapter.map_session(&json!({
            "sessionId": session_id,
            "title": title,
            "cwd": cwd,
            "updatedAt": updated_at,
        }))?;
        sessions.push(mapped);
    }

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
        None => google_tmp_root()?,
    };
    delete_local_session_in_root(&root, id)
}

fn delete_local_session_in_root(tmp_root: &Path, id: &str) -> Result<usize, String> {
    let mut files = Vec::new();
    collect_files_recursively(tmp_root, &mut files)?;
    let mut removed = 0usize;

    for file_path in files {
        if !is_google_session_file(&file_path) {
            continue;
        }
        let value = read_json_file(&file_path)?;
        if value.get("sessionId").and_then(Value::as_str) != Some(id) {
            continue;
        }

        fs::remove_file(&file_path)
            .map_err(|err| format!("failed to delete {}: {err}", file_path.display()))?;
        removed += 1;
    }

    Ok(removed)
}

pub(crate) fn delete_all_local_sessions_at_root(
    root_override: Option<&Path>,
) -> Result<usize, String> {
    let root = match root_override {
        Some(value) => value.to_path_buf(),
        None => google_tmp_root()?,
    };
    delete_all_local_sessions_in_root(&root)
}

fn delete_all_local_sessions_in_root(tmp_root: &Path) -> Result<usize, String> {
    let mut files = Vec::new();
    collect_files_recursively(tmp_root, &mut files)?;
    let mut removed = 0usize;

    for file_path in files {
        if !is_google_session_file(&file_path) {
            continue;
        }

        fs::remove_file(&file_path)
            .map_err(|err| format!("failed to delete {}: {err}", file_path.display()))?;
        removed += 1;
    }

    Ok(removed)
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

fn is_google_session_file(path: &Path) -> bool {
    let Some(name) = path.file_name().and_then(|name| name.to_str()) else {
        return false;
    };
    name.starts_with("session-") && name.ends_with(".json")
}

fn read_json_file(path: &Path) -> Result<Value, String> {
    let mut content = String::new();
    File::open(path)
        .map_err(|err| format!("failed to open {}: {err}", path.display()))?
        .read_to_string(&mut content)
        .map_err(|err| format!("failed to read {}: {err}", path.display()))?;
    serde_json::from_str(&content)
        .map_err(|err| format!("failed to parse {}: {err}", path.display()))
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
        GoogleSessionsAdapter, SessionsAdapter, delete_all_local_sessions_in_root,
        delete_local_session_in_root, list_local_sessions_in_root,
    };
    use crate::conversations::contracts::SessionProvider;
    use serde_json::json;
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn maps_google_session() {
        let adapter = GoogleSessionsAdapter;
        let value = json!({
            "sessionId": "session-1",
            "title": "Ship release",
            "cwd": "/repo",
            "updatedAt": "2026-04-11T12:30:00Z"
        });

        let mapped = adapter.map_session(&value).expect("session should map");
        assert_eq!(mapped.provider, SessionProvider::Google);
        assert_eq!(mapped.id, "session-1");
        assert_eq!(mapped.name, "Ship release");
        assert_eq!(mapped.cwd, "/repo");
        assert_eq!(mapped.updated_at, "2026-04-11T12:30:00Z");
    }

    #[test]
    fn maps_numeric_updated_at() {
        let adapter = GoogleSessionsAdapter;
        let value = json!({
            "sessionId": "session-2",
            "title": "Debug",
            "cwd": "/repo",
            "updatedAt": 1712836800
        });

        let mapped = adapter.map_session(&value).expect("session should map");
        assert_eq!(mapped.updated_at, "1712836800");
    }

    #[test]
    fn rejects_missing_fields() {
        let adapter = GoogleSessionsAdapter;
        let err = adapter
            .map_session(&json!({"sessionId":"session-3"}))
            .expect_err("mapping should fail");
        assert!(err.contains("missing required field"));
    }

    #[test]
    fn list_and_delete_use_local_store_layout() {
        let root = create_temp_dir();
        let chats_dir = root.join(".gemini").join("tmp").join("user").join("chats");
        fs::create_dir_all(&chats_dir).expect("chats directory should be created");

        fs::write(
            chats_dir.join("session-1.json"),
            r#"{"sessionId":"g-1","lastUpdated":"2026-04-11T10:00:00Z","messages":[{"type":"user","content":[{"text":"Hello"}]}]}"#,
        )
        .expect("session-1 should be written");
        fs::write(
            chats_dir.join("session-2.json"),
            r#"{"sessionId":"g-2","title":"Named","cwd":"/repo","updatedAt":"2026-04-11T11:00:00Z"}"#,
        )
        .expect("session-2 should be written");

        let list_root = root.join(".gemini").join("tmp");
        let sessions = list_local_sessions_in_root(&list_root).expect("sessions should list");
        assert_eq!(sessions.len(), 2);
        assert_eq!(sessions[0].id, "g-2");
        assert_eq!(sessions[1].id, "g-1");

        let deleted = delete_local_session_in_root(&list_root, "g-1").expect("delete should work");
        assert_eq!(deleted, 1);
        let sessions_after_delete =
            list_local_sessions_in_root(&list_root).expect("sessions should list after delete");
        assert_eq!(sessions_after_delete.len(), 1);
        assert_eq!(sessions_after_delete[0].id, "g-2");

        let deleted_all =
            delete_all_local_sessions_in_root(&list_root).expect("delete all should work");
        assert_eq!(deleted_all, 1);
        let sessions_after_delete_all =
            list_local_sessions_in_root(&list_root).expect("sessions should list after delete all");
        assert!(sessions_after_delete_all.is_empty());
    }

    fn create_temp_dir() -> PathBuf {
        let suffix = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .expect("time should be valid")
            .as_nanos();
        let path = std::env::temp_dir().join(format!("agent-google-sessions-test-{suffix}"));
        fs::create_dir_all(&path).expect("temp directory should be created");
        path
    }
}
