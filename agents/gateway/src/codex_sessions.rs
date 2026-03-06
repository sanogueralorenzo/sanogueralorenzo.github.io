use anyhow::{Context, Result};
use regex::Regex;
use serde_json::Value;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use tokio::fs;

pub async fn load_desktop_thread_titles(codex_home: &Path) -> Result<HashMap<String, String>> {
    let file_path = codex_home.join(".codex-global-state.json");
    let raw = match fs::read_to_string(&file_path).await {
        Ok(content) => content,
        Err(_) => return Ok(HashMap::new()),
    };

    let parsed: Value = match serde_json::from_str(&raw) {
        Ok(value) => value,
        Err(_) => return Ok(HashMap::new()),
    };

    let titles = parsed
        .get("thread-titles")
        .and_then(Value::as_object)
        .and_then(|obj| obj.get("titles"))
        .and_then(Value::as_object);

    let Some(titles) = titles else {
        return Ok(HashMap::new());
    };

    let mut out = HashMap::new();
    for (thread_id, title) in titles {
        if let Some(title) = title.as_str() {
            let trimmed = title.trim();
            if !trimmed.is_empty() {
                out.insert(thread_id.clone(), trimmed.to_string());
            }
        }
    }

    Ok(out)
}

pub async fn force_session_source(
    thread_id: &str,
    codex_home: &Path,
    source: &str,
    originator: &str,
) -> Result<bool> {
    let sessions_root = codex_home.join("sessions");
    let Some(file_path) = find_session_file_by_thread_id(&sessions_root, thread_id).await? else {
        return Ok(false);
    };

    let raw = match fs::read_to_string(&file_path).await {
        Ok(content) => content,
        Err(_) => return Ok(false),
    };

    let mut lines = raw.lines().map(ToString::to_string).collect::<Vec<_>>();
    if lines.is_empty() || lines[0].trim().is_empty() {
        return Ok(false);
    }

    let mut first: Value = match serde_json::from_str(&lines[0]) {
        Ok(value) => value,
        Err(_) => return Ok(false),
    };

    let Some(payload) = first.get_mut("payload").and_then(Value::as_object_mut) else {
        return Ok(false);
    };

    let current_source = payload
        .get("source")
        .and_then(Value::as_str)
        .unwrap_or_default();
    let current_originator = payload
        .get("originator")
        .and_then(Value::as_str)
        .unwrap_or_default();

    if current_source == source && current_originator == originator {
        return Ok(true);
    }

    payload.insert("source".to_string(), serde_json::json!(source));
    payload.insert("originator".to_string(), serde_json::json!(originator));

    lines[0] = serde_json::to_string(&first)?;
    fs::write(&file_path, lines.join("\n"))
        .await
        .with_context(|| format!("Failed to update session file: {}", file_path.display()))?;

    Ok(true)
}

pub async fn delete_session_by_thread_id(thread_id: &str, codex_home: &Path) -> Result<bool> {
    let root = codex_home.join("sessions");
    let Some(file_path) = find_session_file_by_thread_id(&root, thread_id).await? else {
        return Ok(false);
    };

    match fs::remove_file(&file_path).await {
        Ok(_) => {
            prune_empty_parent_dirs(file_path.parent().unwrap_or(&root), &root).await?;
            Ok(true)
        }
        Err(error) => {
            if error.kind() == std::io::ErrorKind::NotFound {
                return Ok(false);
            }
            Err(error.into())
        }
    }
}

pub async fn load_latest_assistant_message_by_thread_id(
    thread_id: &str,
    codex_home: &Path,
) -> Result<Option<String>> {
    let sessions_root = codex_home.join("sessions");
    let Some(file_path) = find_session_file_by_thread_id(&sessions_root, thread_id).await? else {
        return Ok(None);
    };

    let raw = match fs::read_to_string(&file_path).await {
        Ok(content) => content,
        Err(_) => return Ok(None),
    };

    let mut latest: Option<String> = None;
    for line in raw.lines() {
        if let Some(text) = extract_assistant_text_from_session_line(line) {
            latest = Some(text);
        }
    }

    Ok(latest)
}

async fn find_session_file_by_thread_id(dir: &Path, thread_id: &str) -> Result<Option<PathBuf>> {
    let mut stack = vec![dir.to_path_buf()];

    while let Some(current) = stack.pop() {
        let mut entries = match fs::read_dir(&current).await {
            Ok(items) => items,
            Err(_) => continue,
        };

        while let Some(entry) = entries.next_entry().await? {
            let path = entry.path();
            let file_type = match entry.file_type().await {
                Ok(file_type) => file_type,
                Err(_) => continue,
            };

            if file_type.is_dir() {
                stack.push(path);
                continue;
            }

            if file_type.is_file() {
                let Some(name) = path.file_name().and_then(|n| n.to_str()) else {
                    continue;
                };
                if !name.ends_with(".jsonl") {
                    continue;
                }

                if extract_id_from_name(name).as_deref() == Some(thread_id) {
                    return Ok(Some(path));
                }
            }
        }
    }

    Ok(None)
}

fn extract_id_from_name(file_name: &str) -> Option<String> {
    let stem = file_name.strip_suffix(".jsonl")?;
    let regex =
        Regex::new(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
            .ok()?;
    regex.find(stem).map(|m| m.as_str().to_string())
}

fn extract_assistant_text_from_session_line(line: &str) -> Option<String> {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return None;
    }

    let parsed: Value = serde_json::from_str(trimmed).ok()?;
    if parsed.get("type")?.as_str()? != "response_item" {
        return None;
    }

    let payload = parsed.get("payload")?;
    if payload.get("type")?.as_str()? != "message" {
        return None;
    }
    if payload.get("role")?.as_str()? != "assistant" {
        return None;
    }

    let content = payload.get("content")?.as_array()?;
    let mut parts = Vec::new();
    for item in content {
        if let Some(text) = item.get("text").and_then(Value::as_str) {
            let trimmed_text = text.trim();
            if !trimmed_text.is_empty() {
                parts.push(trimmed_text.to_string());
            }
        }
    }

    if parts.is_empty() {
        None
    } else {
        Some(parts.join("\n\n"))
    }
}

async fn prune_empty_parent_dirs(start_dir: &Path, sessions_root: &Path) -> Result<()> {
    let mut current = start_dir.to_path_buf();

    while is_same_dir_or_child(sessions_root, &current) && current != sessions_root {
        let mut entries = match fs::read_dir(&current).await {
            Ok(items) => items,
            Err(_) => return Ok(()),
        };

        if entries.next_entry().await?.is_some() {
            return Ok(());
        }

        if fs::remove_dir(&current).await.is_err() {
            return Ok(());
        }

        let Some(parent) = current.parent() else {
            break;
        };
        current = parent.to_path_buf();
    }

    Ok(())
}

fn is_same_dir_or_child(parent: &Path, target: &Path) -> bool {
    if let Ok(relative) = target.strip_prefix(parent) {
        return relative.components().next().is_some() || target == parent;
    }
    false
}
