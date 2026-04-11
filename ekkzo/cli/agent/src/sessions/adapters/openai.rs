use super::{SessionsAdapter, required_string_at_path, required_string_or_number};
use crate::sessions::contracts::{SessionContractRecord, SessionProvider};
use serde_json::Value;

pub struct OpenAiSessionsAdapter;

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

#[cfg(test)]
mod tests {
    use super::{OpenAiSessionsAdapter, SessionsAdapter};
    use crate::sessions::contracts::SessionProvider;
    use serde_json::json;

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
}
