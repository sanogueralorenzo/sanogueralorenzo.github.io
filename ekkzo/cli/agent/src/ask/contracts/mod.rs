use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum ProviderName {
    Openai,
    Anthropic,
    Google,
}

impl ProviderName {
    pub fn from_provider_name(provider_name: &str) -> Option<Self> {
        match provider_name {
            "openai" => Some(ProviderName::Openai),
            "anthropic" => Some(ProviderName::Anthropic),
            "google" => Some(ProviderName::Google),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum AskStatus {
    Thinking,
    Completed,
    Interrupted,
    Failed,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct AskError {
    pub message: String,
    pub code: Option<String>,
}

impl AskError {
    pub fn new(message: impl Into<String>, code: Option<String>) -> Self {
        Self {
            message: message.into(),
            code,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct AskEvent {
    pub id: String,
    pub status: AskStatus,
    pub answer: Option<String>,
    pub error: Option<AskError>,
    pub provider: ProviderName,
}

impl AskEvent {
    pub fn new(
        provider: ProviderName,
        id: impl Into<String>,
        status: AskStatus,
        answer: Option<String>,
        error: Option<AskError>,
    ) -> Self {
        Self {
            id: id.into(),
            status,
            answer,
            error,
            provider,
        }
    }

    pub fn thinking(provider: ProviderName, id: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            status: AskStatus::Thinking,
            answer: None,
            error: None,
            provider,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{AskError, AskEvent, AskStatus, ProviderName};
    use serde_json::Value;

    #[test]
    fn serializes_thinking_event_with_expected_shape() {
        let event = AskEvent::thinking(ProviderName::Openai, "ask-1");
        let value = serde_json::to_value(&event).expect("event should serialize");
        assert_eq!(
            value,
            Value::Object(serde_json::Map::from_iter([
                ("id".to_string(), Value::String("ask-1".to_string())),
                ("status".to_string(), Value::String("thinking".to_string())),
                ("answer".to_string(), Value::Null),
                ("error".to_string(), Value::Null),
                ("provider".to_string(), Value::String("openai".to_string())),
            ]))
        );
    }

    #[test]
    fn serializes_failed_event_with_expected_shape() {
        let event = AskEvent::new(
            ProviderName::Anthropic,
            "ask-2",
            AskStatus::Failed,
            None,
            Some(AskError::new(
                "authentication failed",
                Some("401".to_string()),
            )),
        );
        let value = serde_json::to_value(&event).expect("event should serialize");
        assert_eq!(
            value.get("provider"),
            Some(&Value::String("anthropic".to_string()))
        );
        assert_eq!(
            value.get("status"),
            Some(&Value::String("failed".to_string()))
        );
        assert_eq!(value.get("answer"), Some(&Value::Null));
        assert_eq!(
            value
                .get("error")
                .and_then(|error| error.get("message"))
                .and_then(Value::as_str),
            Some("authentication failed")
        );
    }
}
