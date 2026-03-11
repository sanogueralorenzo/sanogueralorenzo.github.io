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

    pub fn codex_home(&self) -> &Path {
        &self.codex_home
    }

    pub fn archived_root(&self) -> PathBuf {
        self.codex_home.join("archived_sessions")
    }

    pub fn collect_sessions(&self) -> Result<Vec<SessionMeta>> {
        let index_titles = self.load_session_index_titles()?;
        if let Some(path) = self.state_db_path()? {
            if let Ok(sessions) = self.collect_sessions_from_db(&path, &index_titles) {
                return Ok(sessions);
            }
        }
        let mut titles = self.load_titles()?;
        for (id, title) in index_titles {
            titles.insert(id, title);
        }
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

    pub fn load_pinned_thread_ids(&self) -> Result<HashSet<String>> {
        let file_path = self.codex_home.join(".codex-global-state.json");
        if !file_path.exists() {
            return Ok(HashSet::new());
        }

        let raw = fs::read_to_string(&file_path)
            .with_context(|| format!("failed to read {}", file_path.display()))?;
        let parsed: Value = serde_json::from_str(&raw)
            .with_context(|| format!("failed to parse {}", file_path.display()))?;

        let mut pinned_ids = HashSet::new();
        let Some(values) = parsed.get("pinned-thread-ids").and_then(Value::as_array) else {
            return Ok(pinned_ids);
        };

        for value in values {
            let Some(id) = value.as_str().map(str::trim) else {
                continue;
            };
            if id.is_empty() {
                continue;
            }
            pinned_ids.insert(id.to_string());
        }

        Ok(pinned_ids)
    }

    pub fn load_session_index_titles(&self) -> Result<HashMap<String, String>> {
        let file_path = self.codex_home.join("session_index.jsonl");
        if !file_path.exists() {
            return Ok(HashMap::new());
        }

        let raw = fs::read_to_string(&file_path)
            .with_context(|| format!("failed to read {}", file_path.display()))?;
        let mut titles = HashMap::new();
        for line in raw.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            let Ok(parsed) = serde_json::from_str::<Value>(trimmed) else {
                continue;
            };
            let Some(id) = parsed.get("id").and_then(Value::as_str).map(str::trim) else {
                continue;
            };
            if id.is_empty() {
                continue;
            }
            let Some(title) = parsed
                .get("thread_name")
                .or_else(|| parsed.get("title"))
                .and_then(Value::as_str)
                .map(str::trim)
            else {
                continue;
            };
            if title.is_empty() {
                continue;
            }
            titles.insert(id.to_string(), title.to_string());
        }

        Ok(titles)
    }

    pub fn archive_session(&self, target: &SessionMeta) -> Result<DeleteResult> {
        if target.archived {
            return Ok(DeleteResult {
                id: target.id.clone(),
                file_path: target.file_path.display().to_string(),
                operation: SessionOperation::Archive,
                status: SessionResultStatus::Succeeded,
                reason: SessionResultReason::Completed,
                message: None,
            });
        }

        let destination = archive_destination(&self.archived_root(), &target.file_path)?;
        move_file_if_exists(&target.file_path, &destination)?;
        self.update_thread_archive_state(&target.id, true, &destination)?;

        Ok(DeleteResult {
            id: target.id.clone(),
            file_path: destination.display().to_string(),
            operation: SessionOperation::Archive,
            status: SessionResultStatus::Succeeded,
            reason: SessionResultReason::Completed,
            message: None,
        })
    }

    pub fn unarchive_session(&self, target: &SessionMeta) -> Result<DeleteResult> {
        if !target.archived {
            return Ok(DeleteResult {
                id: target.id.clone(),
                file_path: target.file_path.display().to_string(),
                operation: SessionOperation::Unarchive,
                status: SessionResultStatus::Succeeded,
                reason: SessionResultReason::Completed,
                message: None,
            });
        }

        let destination = unarchive_destination(&self.sessions_root(), &target.file_path)?;
        move_file_if_exists(&target.file_path, &destination)?;
        self.update_thread_archive_state(&target.id, false, &destination)?;

        Ok(DeleteResult {
            id: target.id.clone(),
            file_path: destination.display().to_string(),
            operation: SessionOperation::Unarchive,
            status: SessionResultStatus::Succeeded,
            reason: SessionResultReason::Completed,
            message: None,
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

        let mut outputs: Vec<Option<DeleteResult>> = (0..targets.len()).map(|_| None).collect();
        let mut ready: Vec<(usize, &SessionMeta)> = Vec::with_capacity(targets.len());

        for (index, target) in targets.iter().copied().enumerate() {
            match self.delete_session_file(target) {
                Ok(_) => ready.push((index, target)),
                Err(error) => {
                    outputs[index] = Some(DeleteResult {
                        id: target.id.clone(),
                        file_path: target.file_path.display().to_string(),
                        operation: SessionOperation::Delete,
                        status: SessionResultStatus::Failed,
                        reason: SessionResultReason::FileDeleteFailed,
                        message: Some(error.to_string()),
                    });
                }
            }
        }

        let ids: Vec<String> = ready.iter().map(|(_, target)| target.id.clone()).collect();

        if !ids.is_empty() {
            if let Err(error) = self.delete_thread_rows(&ids) {
                let detail = format!("file removed but failed deleting DB rows: {error}");
                for (index, target) in &ready {
                    outputs[*index] = Some(DeleteResult {
                        id: target.id.clone(),
                        file_path: target.file_path.display().to_string(),
                        operation: SessionOperation::Delete,
                        status: SessionResultStatus::Failed,
                        reason: SessionResultReason::DbDeleteFailed,
                        message: Some(detail.clone()),
                    });
                }
            } else if let Err(error) = self.delete_thread_titles(&ids) {
                let detail =
                    format!("file removed and DB row deleted but failed title cleanup: {error}");
                for (index, target) in &ready {
                    outputs[*index] = Some(DeleteResult {
                        id: target.id.clone(),
                        file_path: target.file_path.display().to_string(),
                        operation: SessionOperation::Delete,
                        status: SessionResultStatus::Failed,
                        reason: SessionResultReason::TitleCleanupFailed,
                        message: Some(detail.clone()),
                    });
                }
            } else {
                for (index, target) in &ready {
                    outputs[*index] = Some(DeleteResult {
                        id: target.id.clone(),
                        file_path: target.file_path.display().to_string(),
                        operation: SessionOperation::Delete,
                        status: SessionResultStatus::Succeeded,
                        reason: SessionResultReason::Completed,
                        message: None,
                    });
                }
            }
        }

        Ok(outputs.into_iter().flatten().collect())
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

    pub fn read_first_user_message(&self, target: &SessionMeta) -> Result<Option<String>> {
        if let Some(from_db) = self.read_first_user_message_from_db(&target.id)? {
            return Ok(Some(from_db));
        }

        self.read_first_user_message_from_rollout(&target.file_path)
    }

    pub fn set_thread_title(&self, id: &str, title: &str) -> Result<()> {
        let title = title.trim();
        if title.is_empty() {
            bail!("title cannot be empty");
        }

        self.update_thread_title_in_db(id, title)?;
        let _lock = self.acquire_title_write_lock()?;
        self.upsert_thread_title_in_global_state(id, title)?;
        self.upsert_thread_title_in_session_index(id, title)?;

        Ok(())
    }

    pub fn has_non_empty_thread_title(&self, id: &str) -> Result<bool> {
        let Some(path) = self.state_db_path()? else {
            return Ok(false);
        };

        let conn = Connection::open(&path)
            .with_context(|| format!("failed to open {}", path.display()))?;

        let mut statement = match conn.prepare("SELECT title FROM threads WHERE id = ?1 LIMIT 1") {
            Ok(statement) => statement,
            Err(_) => return Ok(false),
        };

        let title: Option<String> = statement
            .query_row(params![id], |row| row.get(0))
            .optional()?;

        Ok(title
            .as_deref()
            .map(str::trim)
            .map(|value| !value.is_empty())
            .unwrap_or(false))
    }

    pub fn list_untitled_thread_candidates(
        &self,
        after_updated_at: Option<i64>,
        after_id: Option<&str>,
        limit: usize,
    ) -> Result<Vec<UntitledThreadCandidate>> {
        if limit == 0 {
            return Ok(Vec::new());
        }

        let Some(path) = self.state_db_path()? else {
            return Ok(Vec::new());
        };

        let conn = Connection::open(&path)
            .with_context(|| format!("failed to open {}", path.display()))?;

        let after_updated_at = after_updated_at.unwrap_or(i64::MIN);
        let after_id = after_id.unwrap_or("");
        let mut statement = match conn.prepare(
            "SELECT id, updated_at
             FROM threads
             WHERE trim(COALESCE(title, '')) = ''
               AND (updated_at > ?1 OR (updated_at = ?1 AND id > ?2))
             ORDER BY updated_at ASC, id ASC
             LIMIT ?3",
        ) {
            Ok(statement) => statement,
            Err(_) => return Ok(Vec::new()),
        };

        let rows =
            statement.query_map(params![after_updated_at, after_id, limit as i64], |row| {
                Ok(UntitledThreadCandidate {
                    id: row.get(0)?,
                    updated_at: row.get(1)?,
                })
            })?;

        let mut candidates = Vec::new();
        for row in rows {
            candidates.push(row?);
        }

        Ok(candidates)
    }

    fn title_write_lock_path(&self) -> PathBuf {
        self.codex_home.join(TITLE_WRITE_LOCK_PATH)
    }

    fn acquire_title_write_lock(&self) -> Result<TitleWriteLock> {
        self.acquire_title_write_lock_with_timeout(TITLE_WRITE_LOCK_TIMEOUT)
    }

    fn acquire_title_write_lock_with_timeout(&self, timeout: Duration) -> Result<TitleWriteLock> {
        let lock_path = self.title_write_lock_path();
        let Some(parent) = lock_path.parent() else {
            bail!("invalid lock path: {}", lock_path.display());
        };
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;

        let file = OpenOptions::new()
            .create(true)
            .read(true)
            .write(true)
            .open(&lock_path)
            .with_context(|| format!("failed to open {}", lock_path.display()))?;

        eprintln!(
            "[codex-sessions:title-lock] waiting path={} timeout_ms={}",
            lock_path.display(),
            timeout.as_millis()
        );

        let start = Instant::now();
        loop {
            let result = unsafe { libc::flock(file.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) };
            if result == 0 {
                eprintln!(
                    "[codex-sessions:title-lock] acquired path={} waited_ms={}",
                    lock_path.display(),
                    start.elapsed().as_millis()
                );
                return Ok(TitleWriteLock { file, lock_path });
            }

            let error = std::io::Error::last_os_error();
            let raw = error.raw_os_error().unwrap_or_default();
            let is_contended = raw == libc::EWOULDBLOCK || raw == libc::EAGAIN;
            if !is_contended {
                return Err(error).with_context(|| {
                    format!(
                        "failed acquiring title-write lock at {}",
                        lock_path.display()
                    )
                });
            }

            if start.elapsed() >= timeout {
                bail!(
                    "timed out waiting {}s for title-write lock at {}",
                    timeout.as_secs(),
                    lock_path.display()
                );
            }

            thread::sleep(TITLE_WRITE_LOCK_POLL_INTERVAL);
        }
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

    fn read_first_user_message_from_db(&self, id: &str) -> Result<Option<String>> {
        let Some(path) = self.state_db_path()? else {
            return Ok(None);
        };

        let conn = Connection::open(&path)
            .with_context(|| format!("failed to open {}", path.display()))?;
        let mut statement =
            match conn.prepare("SELECT first_user_message FROM threads WHERE id = ?1 LIMIT 1") {
                Ok(statement) => statement,
                Err(_) => return Ok(None),
            };

        let value: Option<String> = statement
            .query_row(params![id], |row| row.get(0))
            .optional()?;

        Ok(normalize_optional_string(value))
    }

    fn read_first_user_message_from_rollout(&self, path: &Path) -> Result<Option<String>> {
        if !path.exists() {
            return Ok(None);
        }

        let file =
            fs::File::open(path).with_context(|| format!("failed to open {}", path.display()))?;
        let reader = BufReader::new(file);

        for line in reader.lines() {
            let line =
                line.with_context(|| format!("failed to read line from {}", path.display()))?;
            if let Some(text) = extract_user_text_from_line(&line) {
                return Ok(Some(text));
            }
        }

        Ok(None)
    }

    fn collect_sessions_from_db(
        &self,
        db_path: &Path,
        titles: &HashMap<String, String>,
    ) -> Result<Vec<SessionMeta>> {
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
            let title = titles
                .get(&id)
                .cloned()
                .or_else(|| normalize_optional_string(title_from_db));

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

    fn update_thread_title_in_db(&self, id: &str, title: &str) -> Result<()> {
        let Some(path) = self.state_db_path()? else {
            return Ok(());
        };

        let conn = Connection::open(&path)
            .with_context(|| format!("failed to open {}", path.display()))?;

        conn.execute(
            "UPDATE threads SET title = ?1 WHERE id = ?2",
            params![title, id],
        )?;

        Ok(())
    }

    fn upsert_thread_title_in_global_state(&self, id: &str, title: &str) -> Result<()> {
        let file_path = self.codex_home.join(".codex-global-state.json");
        let mut parsed = if file_path.exists() {
            let raw = fs::read_to_string(&file_path)
                .with_context(|| format!("failed to read {}", file_path.display()))?;
            serde_json::from_str::<Value>(&raw)
                .with_context(|| format!("failed to parse {}", file_path.display()))?
        } else {
            Value::Object(serde_json::Map::new())
        };

        if !parsed.is_object() {
            parsed = Value::Object(serde_json::Map::new());
        }

        let Some(root) = parsed.as_object_mut() else {
            return Ok(());
        };

        let thread_titles_entry = root
            .entry("thread-titles".to_string())
            .or_insert_with(|| Value::Object(serde_json::Map::new()));
        if !thread_titles_entry.is_object() {
            *thread_titles_entry = Value::Object(serde_json::Map::new());
        }
        let Some(thread_titles) = thread_titles_entry.as_object_mut() else {
            return Ok(());
        };

        let titles_entry = thread_titles
            .entry("titles".to_string())
            .or_insert_with(|| Value::Object(serde_json::Map::new()));
        if !titles_entry.is_object() {
            *titles_entry = Value::Object(serde_json::Map::new());
        }
        let Some(titles) = titles_entry.as_object_mut() else {
            return Ok(());
        };
        titles.insert(id.to_string(), Value::String(title.to_string()));

        let order_entry = thread_titles
            .entry("order".to_string())
            .or_insert_with(|| Value::Array(Vec::new()));
        if !order_entry.is_array() {
            *order_entry = Value::Array(Vec::new());
        }
        if let Some(order) = order_entry.as_array_mut() {
            order.retain(|value| value.as_str() != Some(id));
            order.insert(0, Value::String(id.to_string()));
            if order.len() > 200 {
                order.truncate(200);
            }
        }

        let serialized = format!("{}\n", serde_json::to_string_pretty(&parsed)?);
        write_text_file_atomic(&file_path, &serialized)?;

        Ok(())
    }

    fn upsert_thread_title_in_session_index(&self, id: &str, title: &str) -> Result<()> {
        let file_path = self.codex_home.join("session_index.jsonl");
        let raw = if file_path.exists() {
            fs::read_to_string(&file_path)
                .with_context(|| format!("failed to read {}", file_path.display()))?
        } else {
            String::new()
        };

        let mut lines = Vec::new();
        let mut found = false;

        for line in raw.lines() {
            let trimmed = line.trim();
            if trimmed.is_empty() {
                continue;
            }

            let Ok(mut parsed) = serde_json::from_str::<Value>(trimmed) else {
                lines.push(trimmed.to_string());
                continue;
            };

            if parsed.get("id").and_then(Value::as_str).map(str::trim) == Some(id) {
                if let Some(object) = parsed.as_object_mut() {
                    object.insert("thread_name".to_string(), Value::String(title.to_string()));
                    object.insert("title".to_string(), Value::String(title.to_string()));
                    object.insert(
                        "updated_at".to_string(),
                        Value::String(Utc::now().to_rfc3339_opts(SecondsFormat::Micros, true)),
                    );
                }
                found = true;
            }

            lines.push(serde_json::to_string(&parsed)?);
        }

        if !found {
            lines.push(serde_json::to_string(&serde_json::json!({
                "id": id,
                "thread_name": title,
                "title": title,
                "updated_at": Utc::now().to_rfc3339_opts(SecondsFormat::Micros, true),
            }))?);
        }

        let serialized = format!("{}\n", lines.join("\n"));
        write_text_file_atomic(&file_path, &serialized)?;

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
