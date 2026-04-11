mod anthropic;
mod google;
mod openai;

use crate::sessions::contracts::SessionContractRecord;
use serde_json::Value;

use anthropic::AnthropicSessionsAdapter;
use google::GoogleSessionsAdapter;
use openai::OpenAiSessionsAdapter;

pub trait SessionsAdapter {
    fn map_session(&self, value: &Value) -> Result<SessionContractRecord, String>;
}

pub fn map_session_with_provider(
    provider_name: &str,
    value: &Value,
) -> Result<SessionContractRecord, String> {
    match provider_name {
        "openai" => OpenAiSessionsAdapter.map_session(value),
        "google" => GoogleSessionsAdapter.map_session(value),
        "anthropic" => AnthropicSessionsAdapter.map_session(value),
        _ => Err(format!("unknown provider '{provider_name}'")),
    }
}

pub fn map_sessions_with_provider(
    provider_name: &str,
    values: &[Value],
) -> Result<Vec<SessionContractRecord>, String> {
    values
        .iter()
        .map(|value| map_session_with_provider(provider_name, value))
        .collect()
}

fn required_string(value: &Value, key: &str) -> Result<String, String> {
    value
        .get(key)
        .and_then(Value::as_str)
        .map(ToString::to_string)
        .ok_or_else(|| format!("missing required field '{key}'"))
}

fn required_string_or_number(value: &Value, key: &str) -> Result<String, String> {
    let field = value
        .get(key)
        .ok_or_else(|| format!("missing required field '{key}'"))?;

    if let Some(string_value) = field.as_str() {
        return Ok(string_value.to_string());
    }

    if let Some(number_value) = field.as_i64() {
        return Ok(number_value.to_string());
    }

    if let Some(number_value) = field.as_u64() {
        return Ok(number_value.to_string());
    }

    if let Some(number_value) = field.as_f64() {
        return Ok(number_value.to_string());
    }

    Err(format!("invalid field type for '{key}', expected string or number"))
}

fn required_string_at_path(value: &Value, path: &[&str]) -> Result<String, String> {
    let mut current = value;
    for key in path {
        current = current
            .get(key)
            .ok_or_else(|| format!("missing required field '{}'", path.join(".")))?;
    }

    current
        .as_str()
        .map(ToString::to_string)
        .ok_or_else(|| format!("invalid field type for '{}', expected string", path.join(".")))
}

#[cfg(test)]
mod tests {
    use super::{map_session_with_provider, map_sessions_with_provider};
    use serde_json::json;

    #[test]
    fn rejects_unknown_provider() {
        let err = map_session_with_provider("unknown", &json!({ "id": "x" }))
            .expect_err("unknown provider should fail");
        assert!(err.contains("unknown provider"));
    }

    #[test]
    fn maps_multiple_sessions_for_provider() {
        let values = vec![
            json!({"sessionId":"s-1","title":"One","cwd":"/repo","updatedAt":"2026-04-11T00:00:00Z"}),
            json!({"sessionId":"s-2","title":"Two","cwd":"/repo","updatedAt":"2026-04-11T00:10:00Z"}),
        ];

        let mapped = map_sessions_with_provider("google", &values).expect("mapping should work");
        assert_eq!(mapped.len(), 2);
        assert_eq!(mapped[0].id, "s-1");
        assert_eq!(mapped[1].id, "s-2");
    }
}
