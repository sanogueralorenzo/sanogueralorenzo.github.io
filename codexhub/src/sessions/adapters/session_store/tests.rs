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
            std::env::temp_dir().join(format!("codexhub-test-{}", Uuid::new_v4()));
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
            std::env::temp_dir().join(format!("codexhub-test-{}", Uuid::new_v4()));
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

    #[test]
    fn session_index_title_overrides_db_title() {
        let temp_root =
            std::env::temp_dir().join(format!("codexhub-test-{}", Uuid::new_v4()));
        let codex_home = temp_root.join(".codex");
        fs::create_dir_all(&codex_home).expect("create codex home");

        let id = "019cc513-20f1-7452-aaf4-a8c5f32ee074";
        let session_index_path = codex_home.join("session_index.jsonl");
        fs::write(
            &session_index_path,
            format!(
                "{{\"id\":\"{id}\",\"thread_name\":\"Refactor DeviceMode to sealed class\",\"updated_at\":\"2026-03-06T21:35:31.451739Z\"}}\n"
            ),
        )
        .expect("write session index");

        let store = SessionStore { codex_home };
        let titles = store
            .load_session_index_titles()
            .expect("load session index titles");
        assert_eq!(
            titles.get(id).map(String::as_str),
            Some("Refactor DeviceMode to sealed class")
        );

        let _ = fs::remove_dir_all(temp_root);
    }

    #[test]
    fn title_write_lock_times_out_when_contended() {
        let temp_root =
            std::env::temp_dir().join(format!("codexhub-test-{}", Uuid::new_v4()));
        let codex_home = temp_root.join(".codex");
        fs::create_dir_all(&codex_home).expect("create codex home");

        let store = SessionStore { codex_home };
        let _first = store
            .acquire_title_write_lock_with_timeout(Duration::from_millis(200))
            .expect("first lock acquired");

        let error = store
            .acquire_title_write_lock_with_timeout(Duration::from_millis(100))
            .expect_err("second lock should time out");
        let message = error.to_string();
        assert!(message.contains("timed out waiting"));

        let _ = fs::remove_dir_all(temp_root);
    }

    #[test]
    fn load_pinned_thread_ids_reads_global_state_array() {
        let temp_root =
            std::env::temp_dir().join(format!("codexhub-test-{}", Uuid::new_v4()));
        let codex_home = temp_root.join(".codex");
        fs::create_dir_all(&codex_home).expect("create codex home");

        let id_one = "019cc5d1-ec61-7c90-a7d8-2524f8828fd9";
        let id_two = "019cc5d1-ec61-7c90-a7d8-2524f8828fda";
        let global_state_path = codex_home.join(".codex-global-state.json");
        fs::write(
            &global_state_path,
            format!(
                "{{\"pinned-thread-ids\":[\"{id_one}\",\"\",123,\"{id_two}\",\"{id_one}\"]}}\n"
            ),
        )
        .expect("write global state");

        let store = SessionStore { codex_home };
        let pinned_ids = store
            .load_pinned_thread_ids()
            .expect("load pinned thread ids");

        assert_eq!(pinned_ids.len(), 2);
        assert!(pinned_ids.contains(id_one));
        assert!(pinned_ids.contains(id_two));

        let _ = fs::remove_dir_all(temp_root);
    }

    #[test]
    fn title_rewrite_candidate_allows_empty_or_first_prompt_match() {
        assert!(SessionStore::title_is_rewrite_candidate("", "Any first prompt"));
        assert!(SessionStore::title_is_rewrite_candidate(
            "Please summarize this repository layout",
            "Please summarize this repository layout"
        ));
        assert!(SessionStore::title_is_rewrite_candidate(
            "Please summarize this repository layout",
            "Please   summarize\nthis repository\tlayout"
        ));
    }

    #[test]
    fn title_rewrite_candidate_rejects_non_matching_prompt() {
        assert!(!SessionStore::title_is_rewrite_candidate(
            "Compare assert vs kotest performance",
            "Compare Mockito vs MockK performance"
        ));
        assert!(!SessionStore::title_is_rewrite_candidate("simple title", ""));
    }
}
