use crate::shared::models::{DeleteResult, SessionMeta};
use anyhow::{Context, Result, anyhow, bail};
use chrono::{DateTime, TimeZone, Utc};
use rusqlite::{Connection, params};
use serde_json::Value;
use std::collections::{BTreeMap, HashMap};
use std::fs;
use std::io::{BufRead, BufReader};
use std::path::{Path, PathBuf};
use uuid::Uuid;
use walkdir::WalkDir;

pub struct SessionStore {
    codex_home: PathBuf,
}

impl SessionStore {
    pub fn new(override_home: Option<PathBuf>) -> Result<Self> {
        if let Some(home) = override_home {
            return Ok(Self { codex_home: home });
        }

        let home = std::env::var("HOME").context("HOME is not set")?;
        Ok(Self {
            codex_home: PathBuf::from(home).join(".codex"),
        })
    }

    pub fn sessions_root(&self) -> PathBuf {
        self.codex_home.join("sessions")
    }

    pub fn archived_root(&self) -> PathBuf {
        self.codex_home.join("archived_sessions")
    }

    pub fn collect_sessions(&self) -> Result<Vec<SessionMeta>> {
        if let Some(path) = self.state_db_path()? {
            if let Ok(sessions) = self.collect_sessions_from_db(&path) {
                return Ok(sessions);
            }
        }
        let titles = self.load_titles()?;
        self.collect_sessions_from_files(&titles)
    }

    pub fn load_titles(&self) -> Result<HashMap<String, String>> {
        let file_path = self.codex_home.join(".codex-global-state.json");
        if !file_path.exists() {
            return Ok(HashMap::new());
        }

        let raw = fs::read_to_string(&file_path)
            .with_context(|| format!("failed to read {}", file_path.display()))?;
        let parsed: Value = serde_json::from_str(&raw)
            .with_context(|| format!("failed to parse {}", file_path.display()))?;

        let mut titles = HashMap::new();
        let Some(thread_titles) = parsed.get("thread-titles") else {
            return Ok(titles);
        };
        let Some(values) = thread_titles.get("titles") else {
            return Ok(titles);
        };

        if let Some(map) = values.as_object() {
            for (id, value) in map {
                let Some(title) = value.as_str() else {
                    continue;
                };
                let trimmed = title.trim();
                if trimmed.is_empty() {
                    continue;
                }
                titles.insert(id.to_string(), trimmed.to_string());
            }
        }

        Ok(titles)
    }

    pub fn archive_session(&self, target: &SessionMeta) -> Result<DeleteResult> {
        if target.archived {
            return Ok(DeleteResult {
                deleted: true,
                id: target.id.clone(),
                file_path: target.file_path.display().to_string(),
                action: "archived".to_string(),
            });
        }

        let destination = archive_destination(&self.archived_root(), &target.file_path)?;
        move_file_if_exists(&target.file_path, &destination)?;
        self.update_thread_archive_state(&target.id, true, &destination)?;

        Ok(DeleteResult {
            deleted: true,
            id: target.id.clone(),
            file_path: destination.display().to_string(),
            action: "archived".to_string(),
        })
    }

    pub fn unarchive_session(&self, target: &SessionMeta) -> Result<DeleteResult> {
        if !target.archived {
            return Ok(DeleteResult {
                deleted: true,
                id: target.id.clone(),
                file_path: target.file_path.display().to_string(),
                action: "unarchived".to_string(),
            });
        }

        let destination = unarchive_destination(&self.sessions_root(), &target.file_path)?;
        move_file_if_exists(&target.file_path, &destination)?;
        self.update_thread_archive_state(&target.id, false, &destination)?;

        Ok(DeleteResult {
            deleted: true,
            id: target.id.clone(),
            file_path: destination.display().to_string(),
            action: "unarchived".to_string(),
        })
    }

    pub fn delete_session_hard(&self, target: &SessionMeta) -> Result<DeleteResult> {
        let mut results = self.delete_sessions_hard(&[target])?;
        Ok(results.remove(0))
    }

    pub fn delete_sessions_hard(&self, targets: &[&SessionMeta]) -> Result<Vec<DeleteResult>> {
        if targets.is_empty() {
            return Ok(Vec::new());
        }

        for target in targets {
            self.delete_session_file(target)?;
        }

        let ids: Vec<String> = targets.iter().map(|target| target.id.clone()).collect();
        self.delete_thread_rows(&ids)?;
        self.delete_thread_titles(&ids)?;

        Ok(targets
            .iter()
            .map(|target| DeleteResult {
                deleted: true,
                id: target.id.clone(),
                file_path: target.file_path.display().to_string(),
                action: "deleted".to_string(),
            })
            .collect())
    }

    pub fn read_latest_assistant_message(&self, path: &Path) -> Result<Option<String>> {
        if !path.exists() {
            return Ok(None);
        }

        let file =
            fs::File::open(path).with_context(|| format!("failed to open {}", path.display()))?;
        let reader = BufReader::new(file);
        let mut latest: Option<String> = None;

        for line in reader.lines() {
            let line =
                line.with_context(|| format!("failed to read line from {}", path.display()))?;
            if let Some(text) = extract_assistant_text_from_line(&line) {
                latest = Some(text);
            }
        }

        Ok(latest)
    }

    fn state_db_path(&self) -> Result<Option<PathBuf>> {
        if !self.codex_home.exists() {
            return Ok(None);
        }

        let mut best: Option<(u32, PathBuf)> = None;
        for entry in fs::read_dir(&self.codex_home)
            .with_context(|| format!("failed to read {}", self.codex_home.display()))?
        {
            let entry = entry?;
            let path = entry.path();
            if !path.is_file() {
                continue;
            }
            let Some(name) = path.file_name().and_then(|value| value.to_str()) else {
                continue;
            };
            if !name.starts_with("state_") || !name.ends_with(".sqlite") {
                continue;
            }
            let Some(number_text) = name
                .strip_prefix("state_")
                .and_then(|value| value.strip_suffix(".sqlite"))
            else {
                continue;
            };
            let Ok(number) = number_text.parse::<u32>() else {
                continue;
            };

            match &best {
                Some((current, _)) if *current >= number => {}
                _ => best = Some((number, path.clone())),
            }
        }

        Ok(best.map(|(_, path)| path))
    }

    fn collect_sessions_from_db(&self, db_path: &Path) -> Result<Vec<SessionMeta>> {
        let conn = Connection::open(db_path)
            .with_context(|| format!("failed to open {}", db_path.display()))?;

        let mut stmt = conn.prepare(
            "SELECT id, rollout_path, created_at, updated_at, source, cwd, title, archived FROM threads",
        )?;

        let rows = stmt.query_map([], |row| {
            let id: String = row.get(0)?;
            let rollout_path: String = row.get(1)?;
            let created_at: i64 = row.get(2)?;
            let updated_at: i64 = row.get(3)?;
            let source: Option<String> = row.get(4)?;
            let cwd: String = row.get(5)?;
            let title_from_db: Option<String> = row.get(6)?;
            let archived_raw: i64 = row.get(7)?;

            let mut file_path = PathBuf::from(rollout_path);
            if !file_path.is_absolute() {
                file_path = self.codex_home.join(file_path);
            }

            let relative = file_path
                .strip_prefix(&self.codex_home)
                .unwrap_or(&file_path)
                .display()
                .to_string();
            let size_bytes = fs::metadata(&file_path)
                .map(|metadata| metadata.len())
                .unwrap_or(0);

            let source = normalize_optional_string(source);
            let source_kind = source_kind_from_source(source.as_deref());
            let title = normalize_optional_string(title_from_db);

            Ok(SessionMeta {
                id,
                title,
                file_path,
                relative_path: relative,
                cwd: normalize_optional_string(Some(cwd)),
                source,
                source_kind,
                archived: archived_raw == 1,
                created_at: unix_to_utc(created_at),
                last_updated_at: unix_to_utc(updated_at),
                size_bytes,
            })
        })?;

        let mut sessions = Vec::new();
        for row in rows {
            sessions.push(row?);
        }

        Ok(sessions)
    }

    fn collect_sessions_from_files(
        &self,
        titles: &HashMap<String, String>,
    ) -> Result<Vec<SessionMeta>> {
        let mut sessions = Vec::new();

        for (root, archived) in [(self.sessions_root(), false), (self.archived_root(), true)] {
            if !root.exists() {
                continue;
            }

            for entry in WalkDir::new(&root)
                .follow_links(false)
                .sort_by_file_name()
                .into_iter()
                .filter_map(std::result::Result::ok)
            {
                let path = entry.path();
                if !entry.file_type().is_file() {
                    continue;
                }
                if path.extension().and_then(|ext| ext.to_str()) != Some("jsonl") {
                    continue;
                }

                let id = match extract_thread_id(path) {
                    Some(id) => id,
                    None => continue,
                };

                let details = read_session_file(path)?;
                let relative = path
                    .strip_prefix(&self.codex_home)
                    .unwrap_or(path)
                    .display()
                    .to_string();

                sessions.push(SessionMeta {
                    id: id.clone(),
                    title: titles.get(&id).cloned(),
                    file_path: path.to_path_buf(),
                    relative_path: relative,
                    cwd: details.cwd,
                    source_kind: source_kind_from_source(details.source.as_deref()),
                    source: details.source,
                    archived,
                    created_at: details.created_at,
                    last_updated_at: details.last_updated_at,
                    size_bytes: details.size_bytes,
                });
            }
        }

        Ok(sessions)
    }

    fn update_thread_archive_state(
        &self,
        id: &str,
        archived: bool,
        rollout_path: &Path,
    ) -> Result<()> {
        let Some(path) = self.state_db_path()? else {
            return Ok(());
        };

        let conn = Connection::open(&path)
            .with_context(|| format!("failed to open {}", path.display()))?;

        let archived_at: Option<i64> = if archived {
            Some(Utc::now().timestamp())
        } else {
            None
        };
        conn.execute(
            "UPDATE threads SET archived = ?1, archived_at = ?2, rollout_path = ?3 WHERE id = ?4",
            params![
                if archived { 1 } else { 0 },
                archived_at,
                rollout_path.display().to_string(),
                id
            ],
        )?;

        Ok(())
    }

    fn delete_thread_rows(&self, ids: &[String]) -> Result<()> {
        if ids.is_empty() {
            return Ok(());
        }

        let Some(path) = self.state_db_path()? else {
            return Ok(());
        };

        let mut conn = Connection::open(&path)
            .with_context(|| format!("failed to open {}", path.display()))?;
        let transaction = conn.transaction()?;
        {
            let mut statement = transaction.prepare("DELETE FROM threads WHERE id = ?1")?;
            for id in ids {
                statement.execute(params![id])?;
            }
        }
        transaction.commit()?;

        Ok(())
    }

    fn delete_thread_titles(&self, ids: &[String]) -> Result<()> {
        if ids.is_empty() {
            return Ok(());
        }

        let file_path = self.codex_home.join(".codex-global-state.json");
        if !file_path.exists() {
            return Ok(());
        }

        let raw = fs::read_to_string(&file_path)
            .with_context(|| format!("failed to read {}", file_path.display()))?;
        let mut parsed: Value = serde_json::from_str(&raw)
            .with_context(|| format!("failed to parse {}", file_path.display()))?;

        let Some(root) = parsed.as_object_mut() else {
            return Ok(());
        };
        let Some(thread_titles) = root.get_mut("thread-titles").and_then(Value::as_object_mut)
        else {
            return Ok(());
        };
        let Some(titles) = thread_titles
            .get_mut("titles")
            .and_then(Value::as_object_mut)
        else {
            return Ok(());
        };

        let mut changed = false;
        for id in ids {
            if titles.remove(id).is_some() {
                changed = true;
            }
        }
        if !changed {
            return Ok(());
        }

        let serialized = serde_json::to_string_pretty(&parsed)?;
        fs::write(&file_path, format!("{serialized}\n"))
            .with_context(|| format!("failed to write {}", file_path.display()))?;
        Ok(())
    }

    fn delete_session_file(&self, target: &SessionMeta) -> Result<()> {
        if target.file_path.exists() {
            fs::remove_file(&target.file_path)
                .with_context(|| format!("failed to delete {}", target.file_path.display()))?;
            if let Some(parent) = target.file_path.parent() {
                let sessions_root = self.sessions_root();
                if parent.starts_with(&sessions_root) {
                    prune_empty_parent_dirs(parent, &sessions_root)?;
                }
                let archived_root = self.archived_root();
                if parent.starts_with(&archived_root) {
                    prune_empty_parent_dirs(parent, &archived_root)?;
                }
            }
        }

        Ok(())
    }
}

pub fn resolve_session_by_id<'a>(
    sessions: &'a [SessionMeta],
    input: &str,
) -> Result<&'a SessionMeta> {
    if let Some(session) = sessions.iter().find(|session| session.id == input) {
        return Ok(session);
    }

    let matches: Vec<&SessionMeta> = sessions
        .iter()
        .filter(|session| session.id.starts_with(input))
        .collect();

    match matches.len() {
        0 => bail!("no session matches id or prefix '{input}'"),
        1 => Ok(matches[0]),
        _ => {
            let ids: BTreeMap<String, ()> = matches
                .into_iter()
                .map(|session| (session.id.clone(), ()))
                .collect();
            let list = ids.keys().cloned().collect::<Vec<_>>().join(", ");
            bail!("id prefix '{input}' is ambiguous: {list}");
        }
    }
}

#[derive(Debug)]
struct SessionFileDetails {
    cwd: Option<String>,
    source: Option<String>,
    created_at: DateTime<Utc>,
    last_updated_at: DateTime<Utc>,
    size_bytes: u64,
}

fn read_session_file(path: &Path) -> Result<SessionFileDetails> {
    let file =
        fs::File::open(path).with_context(|| format!("failed to open {}", path.display()))?;
    let metadata = file
        .metadata()
        .with_context(|| format!("failed to read metadata for {}", path.display()))?;

    let mut cwd: Option<String> = None;
    let mut source: Option<String> = None;
    let mut earliest: Option<DateTime<Utc>> = None;
    let mut latest: Option<DateTime<Utc>> = None;

    let reader = BufReader::new(file);
    for line in reader.lines() {
        let line = line.with_context(|| format!("failed to read line from {}", path.display()))?;
        let trimmed = line.trim();
        if trimmed.is_empty() {
            continue;
        }

        let parsed: Value = match serde_json::from_str(trimmed) {
            Ok(value) => value,
            Err(_) => continue,
        };

        if parsed.get("type").and_then(Value::as_str) == Some("session_meta") {
            if cwd.is_none() {
                cwd = parsed
                    .get("payload")
                    .and_then(Value::as_object)
                    .and_then(|payload| payload.get("cwd"))
                    .and_then(Value::as_str)
                    .map(str::to_owned);
            }
            if source.is_none() {
                source = parsed
                    .get("payload")
                    .and_then(Value::as_object)
                    .and_then(|payload| payload.get("source"))
                    .and_then(Value::as_str)
                    .map(str::to_owned);
            }
        }

        let Some(ts) = parsed.get("timestamp").and_then(Value::as_str) else {
            continue;
        };
        let Ok(dt) = DateTime::parse_from_rfc3339(ts) else {
            continue;
        };
        let dt_utc = dt.with_timezone(&Utc);

        earliest = Some(match earliest {
            Some(current) if current < dt_utc => current,
            _ => dt_utc,
        });
        latest = Some(match latest {
            Some(current) if current > dt_utc => current,
            _ => dt_utc,
        });
    }

    let created_fallback = metadata
        .created()
        .ok()
        .map(DateTime::<Utc>::from)
        .or_else(|| metadata.modified().ok().map(DateTime::<Utc>::from))
        .unwrap_or_else(Utc::now);
    let updated_fallback = metadata
        .modified()
        .ok()
        .map(DateTime::<Utc>::from)
        .unwrap_or_else(Utc::now);

    Ok(SessionFileDetails {
        cwd,
        source,
        created_at: earliest.unwrap_or(created_fallback),
        last_updated_at: latest.unwrap_or(updated_fallback),
        size_bytes: metadata.len(),
    })
}

fn archive_destination(archived_root: &Path, source_path: &Path) -> Result<PathBuf> {
    let file_name = source_path
        .file_name()
        .ok_or_else(|| anyhow!("session file has no name"))?;
    Ok(archived_root.join(file_name))
}

fn unarchive_destination(sessions_root: &Path, source_path: &Path) -> Result<PathBuf> {
    let file_name = source_path
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| anyhow!("session file has invalid name"))?;

    if let Some((year, month, day)) = extract_rollout_date_parts(file_name) {
        return Ok(sessions_root
            .join(year)
            .join(month)
            .join(day)
            .join(file_name));
    }

    Ok(sessions_root.join(file_name))
}

fn extract_rollout_date_parts(file_name: &str) -> Option<(String, String, String)> {
    let rest = file_name.strip_prefix("rollout-")?;
    let mut parts = rest.split('-');
    let year = parts.next()?;
    let month = parts.next()?;
    let day_with_time = parts.next()?;
    let day = day_with_time.split('T').next()?;

    if year.len() != 4 || month.len() != 2 || day.len() != 2 {
        return None;
    }
    if !year.chars().all(|ch| ch.is_ascii_digit())
        || !month.chars().all(|ch| ch.is_ascii_digit())
        || !day.chars().all(|ch| ch.is_ascii_digit())
    {
        return None;
    }

    Some((year.to_string(), month.to_string(), day.to_string()))
}

fn move_file_if_exists(source: &Path, destination: &Path) -> Result<()> {
    if source == destination {
        return Ok(());
    }

    if !source.exists() {
        return Ok(());
    }

    let parent = destination
        .parent()
        .ok_or_else(|| anyhow!("destination has no parent"))?;
    fs::create_dir_all(parent).with_context(|| format!("failed to create {}", parent.display()))?;

    match fs::rename(source, destination) {
        Ok(_) => Ok(()),
        Err(_) => {
            fs::copy(source, destination).with_context(|| {
                format!(
                    "failed to copy {} to {}",
                    source.display(),
                    destination.display()
                )
            })?;
            fs::remove_file(source)
                .with_context(|| format!("failed to remove {}", source.display()))?;
            Ok(())
        }
    }
}

fn normalize_optional_string(value: Option<String>) -> Option<String> {
    value.and_then(|text| {
        let trimmed = text.trim();
        if trimmed.is_empty() {
            None
        } else {
            Some(trimmed.to_string())
        }
    })
}

fn source_kind_from_source(source: Option<&str>) -> String {
    let normalized = source
        .map(str::trim)
        .unwrap_or_default()
        .to_ascii_lowercase();

    match normalized.as_str() {
        "cli" => "cli",
        "vscode" => "vscode",
        "exec" => "exec",
        "appserver" | "app-server" | "app_server" | "app server" => "appServer",
        "subagent" | "sub-agent" | "sub_agent" => "subAgent",
        "subagentreview" | "sub-agent-review" | "sub_agent_review" => "subAgentReview",
        "subagentcompact" | "sub-agent-compact" | "sub_agent_compact" => "subAgentCompact",
        "subagentthreadspawn" | "sub-agent-thread-spawn" | "sub_agent_thread_spawn" => {
            "subAgentThreadSpawn"
        }
        "subagentother" | "sub-agent-other" | "sub_agent_other" => "subAgentOther",
        _ => "unknown",
    }
    .to_string()
}

fn unix_to_utc(seconds: i64) -> DateTime<Utc> {
    Utc.timestamp_opt(seconds, 0)
        .single()
        .unwrap_or_else(Utc::now)
}

fn extract_assistant_text_from_line(line: &str) -> Option<String> {
    let trimmed = line.trim();
    if trimmed.is_empty() {
        return None;
    }

    let parsed: Value = serde_json::from_str(trimmed).ok()?;
    if parsed.get("type").and_then(Value::as_str) != Some("response_item") {
        return None;
    }

    let payload = parsed.get("payload")?;
    if payload.get("type").and_then(Value::as_str) != Some("message") {
        return None;
    }
    if payload.get("role").and_then(Value::as_str) != Some("assistant") {
        return None;
    }

    let content = payload.get("content")?.as_array()?;
    let mut parts = Vec::new();
    for item in content {
        let Some(text) = item.get("text").and_then(Value::as_str) else {
            continue;
        };
        let trimmed = text.trim();
        if !trimmed.is_empty() {
            parts.push(trimmed.to_string());
        }
    }

    if parts.is_empty() {
        None
    } else {
        Some(parts.join("\n\n"))
    }
}

fn prune_empty_parent_dirs(start: &Path, root: &Path) -> Result<()> {
    let mut current = start.to_path_buf();

    loop {
        if current == root {
            break;
        }
        if !current.starts_with(root) {
            break;
        }

        let mut entries = fs::read_dir(&current)
            .with_context(|| format!("failed to read dir {}", current.display()))?;
        if entries.next().is_some() {
            break;
        }

        fs::remove_dir(&current)
            .with_context(|| format!("failed to remove dir {}", current.display()))?;

        let Some(parent) = current.parent() else {
            break;
        };
        current = parent.to_path_buf();
    }

    Ok(())
}

fn extract_thread_id(path: &Path) -> Option<String> {
    let stem = path.file_stem()?.to_string_lossy();
    let candidate = stem.rsplit('-').take(5).collect::<Vec<_>>();
    if candidate.len() != 5 {
        return None;
    }

    let reversed = candidate.into_iter().rev().collect::<Vec<_>>().join("-");
    if Uuid::parse_str(&reversed).is_ok() {
        return Some(reversed);
    }

    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_thread_id_from_rollout_file_name() {
        let path =
            PathBuf::from("rollout-2026-03-06T17-03-15-019cc5d1-ec61-7c90-a7d8-2524f8828fd9.jsonl");

        let id = extract_thread_id(&path).expect("expected id");
        assert_eq!(id, "019cc5d1-ec61-7c90-a7d8-2524f8828fd9");
    }

    #[test]
    fn rejects_invalid_thread_id_name() {
        let path = PathBuf::from("rollout-bad-id.jsonl");
        assert!(extract_thread_id(&path).is_none());
    }

    #[test]
    fn parses_rollout_date_parts() {
        let value = extract_rollout_date_parts(
            "rollout-2026-03-06T17-03-15-019cc5d1-ec61-7c90-a7d8-2524f8828fd9.jsonl",
        );

        assert_eq!(
            value,
            Some(("2026".to_string(), "03".to_string(), "06".to_string()))
        );
    }

    #[test]
    fn hard_delete_removes_global_state_title_entry() {
        let id = "019cc5d1-ec61-7c90-a7d8-2524f8828fd9";
        let temp_root =
            std::env::temp_dir().join(format!("codex-sessions-test-{}", Uuid::new_v4()));
        let codex_home = temp_root.join(".codex");
        let sessions_dir = codex_home
            .join("sessions")
            .join("2026")
            .join("03")
            .join("06");
        fs::create_dir_all(&sessions_dir).expect("create sessions dir");

        let session_file = sessions_dir
            .join("rollout-2026-03-06T17-03-15-019cc5d1-ec61-7c90-a7d8-2524f8828fd9.jsonl");
        fs::write(&session_file, "{\"type\":\"session_meta\"}\n").expect("write session file");

        let global_state_path = codex_home.join(".codex-global-state.json");
        fs::write(
            &global_state_path,
            format!(
                "{{\"thread-titles\":{{\"titles\":{{\"{id}\":\"Delete me\",\"keep\":\"Keep me\"}}}}}}\n"
            ),
        )
        .expect("write global state");

        let store = SessionStore { codex_home };
        let now = Utc::now();
        let session = SessionMeta {
            id: id.to_string(),
            title: Some("Delete me".to_string()),
            file_path: session_file.clone(),
            relative_path: "sessions/2026/03/06/test.jsonl".to_string(),
            cwd: None,
            source: None,
            source_kind: "unknown".to_string(),
            archived: false,
            created_at: now,
            last_updated_at: now,
            size_bytes: 0,
        };

        store
            .delete_session_hard(&session)
            .expect("hard delete succeeds");

        let raw = fs::read_to_string(&global_state_path).expect("read global state");
        let parsed: Value = serde_json::from_str(&raw).expect("parse global state");
        let titles = parsed
            .get("thread-titles")
            .and_then(|value| value.get("titles"))
            .and_then(Value::as_object)
            .expect("titles object");
        assert!(!titles.contains_key(id));
        assert_eq!(titles.get("keep").and_then(Value::as_str), Some("Keep me"));
        assert!(!session_file.exists());

        let _ = fs::remove_dir_all(temp_root);
    }

    #[test]
    fn batch_hard_delete_removes_multiple_titles() {
        let id_one = "019cc5d1-ec61-7c90-a7d8-2524f8828fd9";
        let id_two = "019cc5d1-ec61-7c90-a7d8-2524f8828fda";
        let temp_root =
            std::env::temp_dir().join(format!("codex-sessions-test-{}", Uuid::new_v4()));
        let codex_home = temp_root.join(".codex");
        let sessions_dir = codex_home
            .join("sessions")
            .join("2026")
            .join("03")
            .join("06");
        fs::create_dir_all(&sessions_dir).expect("create sessions dir");

        let session_file_one = sessions_dir
            .join("rollout-2026-03-06T17-03-15-019cc5d1-ec61-7c90-a7d8-2524f8828fd9.jsonl");
        let session_file_two = sessions_dir
            .join("rollout-2026-03-06T17-03-15-019cc5d1-ec61-7c90-a7d8-2524f8828fda.jsonl");
        fs::write(&session_file_one, "{\"type\":\"session_meta\"}\n")
            .expect("write session file 1");
        fs::write(&session_file_two, "{\"type\":\"session_meta\"}\n")
            .expect("write session file 2");

        let global_state_path = codex_home.join(".codex-global-state.json");
        fs::write(
            &global_state_path,
            format!(
                "{{\"thread-titles\":{{\"titles\":{{\"{id_one}\":\"Delete one\",\"{id_two}\":\"Delete two\",\"keep\":\"Keep me\"}}}}}}\n"
            ),
        )
        .expect("write global state");

        let store = SessionStore { codex_home };
        let now = Utc::now();
        let session_one = SessionMeta {
            id: id_one.to_string(),
            title: Some("Delete one".to_string()),
            file_path: session_file_one.clone(),
            relative_path: "sessions/2026/03/06/one.jsonl".to_string(),
            cwd: None,
            source: None,
            source_kind: "unknown".to_string(),
            archived: false,
            created_at: now,
            last_updated_at: now,
            size_bytes: 0,
        };
        let session_two = SessionMeta {
            id: id_two.to_string(),
            title: Some("Delete two".to_string()),
            file_path: session_file_two.clone(),
            relative_path: "sessions/2026/03/06/two.jsonl".to_string(),
            cwd: None,
            source: None,
            source_kind: "unknown".to_string(),
            archived: false,
            created_at: now,
            last_updated_at: now,
            size_bytes: 0,
        };

        store
            .delete_sessions_hard(&[&session_one, &session_two])
            .expect("batch hard delete succeeds");

        let raw = fs::read_to_string(&global_state_path).expect("read global state");
        let parsed: Value = serde_json::from_str(&raw).expect("parse global state");
        let titles = parsed
            .get("thread-titles")
            .and_then(|value| value.get("titles"))
            .and_then(Value::as_object)
            .expect("titles object");
        assert!(!titles.contains_key(id_one));
        assert!(!titles.contains_key(id_two));
        assert_eq!(titles.get("keep").and_then(Value::as_str), Some("Keep me"));
        assert!(!session_file_one.exists());
        assert!(!session_file_two.exists());

        let _ = fs::remove_dir_all(temp_root);
    }
}
