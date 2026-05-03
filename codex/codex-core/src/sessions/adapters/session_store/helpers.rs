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

fn normalize_title_compare_text(value: &str) -> String {
    value.split_whitespace().collect::<Vec<_>>().join(" ")
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

fn extract_user_text_from_line(line: &str) -> Option<String> {
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
    if payload.get("role").and_then(Value::as_str) != Some("user") {
        return None;
    }

    let content = payload.get("content")?.as_array()?;
    let mut parts = Vec::new();
    for item in content {
        let Some(text) = item.get("text").and_then(Value::as_str) else {
            continue;
        };
        let value = text.trim();
        if value.is_empty() || is_instruction_payload_text(value) {
            continue;
        }
        parts.push(value.to_string());
    }

    if parts.is_empty() {
        None
    } else {
        Some(parts.join("\n\n"))
    }
}

fn is_instruction_payload_text(value: &str) -> bool {
    let lower = value.to_ascii_lowercase();
    lower.starts_with("# agents.md instructions for ")
        || lower.starts_with("<environment_context>")
        || lower.starts_with("<instructions>")
        || lower.starts_with("<skill>")
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

fn write_text_file_atomic(path: &Path, contents: &str) -> Result<()> {
    let Some(parent) = path.parent() else {
        bail!("path has no parent: {}", path.display());
    };
    fs::create_dir_all(parent).with_context(|| format!("failed to create {}", parent.display()))?;

    let file_name = path
        .file_name()
        .and_then(|value| value.to_str())
        .ok_or_else(|| anyhow!("invalid file name for {}", path.display()))?;
    let nonce = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_else(|_| Duration::from_secs(0))
        .as_nanos();
    let tmp_path = parent.join(format!(".{file_name}.tmp-{}-{nonce}", std::process::id()));

    let result = (|| -> Result<()> {
        let mut file = OpenOptions::new()
            .create_new(true)
            .write(true)
            .open(&tmp_path)
            .with_context(|| format!("failed to create {}", tmp_path.display()))?;
        file.write_all(contents.as_bytes())
            .with_context(|| format!("failed to write {}", tmp_path.display()))?;
        file.sync_all()
            .with_context(|| format!("failed to fsync {}", tmp_path.display()))?;
        drop(file);

        fs::rename(&tmp_path, path).with_context(|| {
            format!(
                "failed to rename {} to {}",
                tmp_path.display(),
                path.display()
            )
        })?;

        let dir = File::open(parent)
            .with_context(|| format!("failed to open directory {}", parent.display()))?;
        dir.sync_all()
            .with_context(|| format!("failed to fsync directory {}", parent.display()))?;

        Ok(())
    })();

    if result.is_err() {
        let _ = fs::remove_file(&tmp_path);
    }

    result
}
