use super::{SessionsAdapter, required_string, required_string_or_number};
use crate::sessions::contracts::{SessionContractRecord, SessionProvider};
use serde_json::{Value, json};
use std::env;
use std::fs::{self, File};
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use std::time::UNIX_EPOCH;

pub struct AnthropicSessionsAdapter;

const PROJECTS_SUBDIR: &str = "projects";

impl SessionsAdapter for AnthropicSessionsAdapter {
    fn map_session(&self, value: &Value) -> Result<SessionContractRecord, String> {
        let id = value
            .get("sessionId")
            .and_then(Value::as_str)
            .map(ToString::to_string)
            .or_else(|| {
                value
                    .get("session_id")
                    .and_then(Value::as_str)
                    .map(ToString::to_string)
            })
            .ok_or_else(|| "missing required field 'sessionId'".to_string())?;

        let name = value
            .get("summary")
            .and_then(Value::as_str)
            .map(ToString::to_string)
            .or_else(|| {
                value
                    .get("customTitle")
                    .and_then(Value::as_str)
                    .map(ToString::to_string)
            })
            .ok_or_else(|| "missing required field 'summary'".to_string())?;

        let updated_at = if value.get("updatedAt").is_some() {
            required_string_or_number(value, "updatedAt")?
        } else if value.get("lastModified").is_some() {
            required_string_or_number(value, "lastModified")?
        } else {
            return Err("missing required field 'updatedAt'".to_string());
        };

        Ok(SessionContractRecord {
            provider: SessionProvider::Anthropic,
            id,
            name,
            cwd: required_string(value, "cwd")?,
            updated_at,
        })
    }
}

pub fn resume_command(id: &str) -> Vec<String> {
    vec!["claude".to_string(), "--resume".to_string(), id.to_string()]
}

fn anthropic_projects_root() -> Result<PathBuf, String> {
    let home = env::var("HOME").map_err(|_| "HOME is not set".to_string())?;
    Ok(PathBuf::from(home).join(".claude").join(PROJECTS_SUBDIR))
}

pub(crate) fn list_local_sessions_at_root(
    root_override: Option<&Path>,
) -> Result<Vec<SessionContractRecord>, String> {
    let root = match root_override {
        Some(value) => value.to_path_buf(),
        None => anthropic_projects_root()?,
    };
    list_local_sessions_in_root(&root)
}

fn list_local_sessions_in_root(projects_root: &Path) -> Result<Vec<SessionContractRecord>, String> {
    let mut files = Vec::new();
    collect_files_recursively(projects_root, &mut files)?;
    let mut sessions = Vec::new();

    for file_path in files {
        if file_path.extension().and_then(|ext| ext.to_str()) != Some("jsonl") {
            continue;
        }

        let Some(id) = file_path
            .file_stem()
            .and_then(|stem| stem.to_str())
            .map(ToString::to_string)
        else {
            continue;
        };

        let (name, cwd) = read_name_and_cwd(&file_path)?;
        let updated_at = file_mtime_epoch_seconds(&file_path).unwrap_or_else(|| "0".to_string());
        let mapped = AnthropicSessionsAdapter.map_session(&json!({
            "sessionId": id,
            "summary": if name.is_empty() { id.clone() } else { name },
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

fn read_name_and_cwd(file_path: &Path) -> Result<(String, String), String> {
    let file =
        File::open(file_path).map_err(|err| format!("failed to open {}: {err}", file_path.display()))?;
    let reader = BufReader::new(file);

    let mut name = String::new();
    let mut cwd = String::new();
    for line in reader.lines().take(300) {
        let line = line.map_err(|err| format!("failed to read {}: {err}", file_path.display()))?;
        if line.trim().is_empty() {
            continue;
        }
        let Ok(value) = serde_json::from_str::<Value>(&line) else {
            continue;
        };

        if cwd.is_empty() {
            cwd = value
                .get("cwd")
                .and_then(Value::as_str)
                .unwrap_or("")
                .to_string();
        }

        if name.is_empty() {
            name = value
                .get("customTitle")
                .and_then(Value::as_str)
                .or_else(|| value.get("summary").and_then(Value::as_str))
                .or_else(|| {
                    value
                        .get("message")
                        .and_then(|message| message.get("content"))
                        .and_then(Value::as_array)
                        .and_then(|content| content.first())
                        .and_then(|first| first.get("text"))
                        .and_then(Value::as_str)
                })
                .unwrap_or("")
                .to_string();
        }

        if !name.is_empty() && !cwd.is_empty() {
            break;
        }
    }

    Ok((name, cwd))
}

pub(crate) fn delete_local_session_at_root(
    id: &str,
    root_override: Option<&Path>,
) -> Result<usize, String> {
    let root = match root_override {
        Some(value) => value.to_path_buf(),
        None => anthropic_projects_root()?,
    };
    delete_local_session_in_root(&root, id)
}

fn delete_local_session_in_root(projects_root: &Path, id: &str) -> Result<usize, String> {
    let mut files = Vec::new();
    collect_files_recursively(projects_root, &mut files)?;
    let mut removed = 0usize;

    for file_path in files {
        if file_path.extension().and_then(|ext| ext.to_str()) != Some("jsonl") {
            continue;
        }
        let Some(stem) = file_path.file_stem().and_then(|stem| stem.to_str()) else {
            continue;
        };
        if stem != id {
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
        None => anthropic_projects_root()?,
    };
    delete_all_local_sessions_in_root(&root)
}

fn delete_all_local_sessions_in_root(projects_root: &Path) -> Result<usize, String> {
    let mut files = Vec::new();
    collect_files_recursively(projects_root, &mut files)?;
    let mut removed = 0usize;

    for file_path in files {
        if file_path.extension().and_then(|ext| ext.to_str()) != Some("jsonl") {
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

fn file_mtime_epoch_seconds(path: &Path) -> Option<String> {
    let metadata = fs::metadata(path).ok()?;
    let modified = metadata.modified().ok()?;
    let duration = modified.duration_since(UNIX_EPOCH).ok()?;
    Some(duration.as_secs().to_string())
}

#[cfg(test)]
mod tests {
    use super::{
        AnthropicSessionsAdapter, SessionsAdapter, delete_all_local_sessions_in_root,
        delete_local_session_in_root, list_local_sessions_in_root,
    };
    use crate::sessions::contracts::SessionProvider;
    use serde_json::json;
    use std::fs;
    use std::path::PathBuf;
    use std::time::{SystemTime, UNIX_EPOCH};

    #[test]
    fn maps_anthropic_session() {
        let adapter = AnthropicSessionsAdapter;
        let value = json!({
            "sessionId": "session-1",
            "summary": "Fix build",
            "cwd": "/repo",
            "updatedAt": "2026-04-11T13:00:00Z"
        });

        let mapped = adapter.map_session(&value).expect("session should map");
        assert_eq!(mapped.provider, SessionProvider::Anthropic);
        assert_eq!(mapped.id, "session-1");
        assert_eq!(mapped.name, "Fix build");
        assert_eq!(mapped.cwd, "/repo");
        assert_eq!(mapped.updated_at, "2026-04-11T13:00:00Z");
    }

    #[test]
    fn supports_legacy_field_names() {
        let adapter = AnthropicSessionsAdapter;
        let value = json!({
            "session_id": "session-2",
            "customTitle": "Rename me",
            "cwd": "/repo",
            "lastModified": 1712836800
        });

        let mapped = adapter.map_session(&value).expect("session should map");
        assert_eq!(mapped.id, "session-2");
        assert_eq!(mapped.name, "Rename me");
        assert_eq!(mapped.updated_at, "1712836800");
    }

    #[test]
    fn rejects_missing_fields() {
        let adapter = AnthropicSessionsAdapter;
        let err = adapter
            .map_session(&json!({"sessionId":"session-3"}))
            .expect_err("mapping should fail");
        assert!(err.contains("missing required field"));
    }

    #[test]
    fn list_and_delete_use_local_store_layout() {
        let root = create_temp_dir();
        let project_dir = root.join(".claude").join("projects").join("my-project");
        fs::create_dir_all(&project_dir).expect("project directory should be created");

        fs::write(
            project_dir.join("session-1.jsonl"),
            r#"{"type":"user","message":{"content":[{"type":"text","text":"Build release"}]},"cwd":"/repo-a"}
{"type":"summary","summary":"Build release summary"}
"#,
        )
        .expect("session-1 file should be written");
        fs::write(
            project_dir.join("session-2.jsonl"),
            r#"{"type":"user","message":{"content":[{"type":"text","text":"Fix tests"}]},"cwd":"/repo-b"}"#,
        )
        .expect("session-2 file should be written");

        let list_root = root.join(".claude").join("projects");
        let sessions = list_local_sessions_in_root(&list_root).expect("sessions should list");
        assert_eq!(sessions.len(), 2);
        assert!(sessions.iter().any(|session| session.id == "session-1"));
        assert!(sessions.iter().any(|session| session.id == "session-2"));

        let deleted = delete_local_session_in_root(&list_root, "session-1").expect("delete should work");
        assert_eq!(deleted, 1);
        let sessions_after_delete =
            list_local_sessions_in_root(&list_root).expect("sessions should list after delete");
        assert_eq!(sessions_after_delete.len(), 1);
        assert_eq!(sessions_after_delete[0].id, "session-2");

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
        let path = std::env::temp_dir().join(format!("agent-anthropic-sessions-test-{suffix}"));
        fs::create_dir_all(&path).expect("temp directory should be created");
        path
    }
}
