use super::{SessionsAdapter, required_string, required_string_or_number};
use crate::sessions::contracts::{SessionContractRecord, SessionProvider};
use serde_json::Value;

pub struct AnthropicSessionsAdapter;

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

#[cfg(test)]
mod tests {
    use super::{AnthropicSessionsAdapter, SessionsAdapter};
    use crate::sessions::contracts::SessionProvider;
    use serde_json::json;

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
}
