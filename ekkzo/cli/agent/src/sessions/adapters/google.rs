use super::{SessionsAdapter, required_string, required_string_or_number};
use crate::sessions::contracts::{SessionContractRecord, SessionProvider};
use serde_json::Value;

pub struct GoogleSessionsAdapter;

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

#[cfg(test)]
mod tests {
    use super::{GoogleSessionsAdapter, SessionsAdapter};
    use crate::sessions::contracts::SessionProvider;
    use serde_json::json;

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
}
