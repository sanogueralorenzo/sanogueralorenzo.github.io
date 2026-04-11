use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct TurnStartedEvent {
    pub id: String,
    pub status: TurnStatus,
}

impl TurnStartedEvent {
    pub fn new(id: impl Into<String>) -> Self {
        Self {
            id: id.into(),
            status: TurnStatus::Thinking,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub enum TurnEvent {
    Started(TurnStartedEvent),
    Completed(TurnCompletedEvent),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct TurnCompletedEvent {
    pub id: String,
    pub status: TurnStatus,
    pub answer: Option<String>,
    pub error: Option<TurnError>,
}

impl TurnCompletedEvent {
    pub fn new(
        id: impl Into<String>,
        status: TurnStatus,
        answer: Option<String>,
        error: Option<TurnError>,
    ) -> Self {
        Self {
            id: id.into(),
            status,
            answer,
            error,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum TurnStatus {
    Thinking,
    Completed,
    Interrupted,
    Failed,
}

impl TurnStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            TurnStatus::Thinking => "thinking",
            TurnStatus::Completed => "completed",
            TurnStatus::Interrupted => "interrupted",
            TurnStatus::Failed => "failed",
        }
    }

    pub fn from_codex_status(status: &str) -> Option<Self> {
        match status {
            "completed" => Some(TurnStatus::Completed),
            "interrupted" => Some(TurnStatus::Interrupted),
            "failed" => Some(TurnStatus::Failed),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct TurnError {
    pub message: String,
    pub code: Option<String>,
}

impl TurnError {
    pub fn new(message: impl Into<String>, code: Option<String>) -> Self {
        Self {
            message: message.into(),
            code,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{TurnCompletedEvent, TurnError, TurnStartedEvent, TurnStatus};
    use serde_json::Value;

    #[test]
    fn started_event_matches_contract() {
        let event = TurnStartedEvent::new("thread-1");
        assert_eq!(event.id, "thread-1");
        assert_eq!(event.status, TurnStatus::Thinking);
    }

    #[test]
    fn completed_event_matches_contract() {
        let error = TurnError::new("failed to run tool", Some(String::from("tool_failure")));
        let event = TurnCompletedEvent::new("thread-1", TurnStatus::Failed, None, Some(error));

        assert_eq!(event.id, "thread-1");
        assert_eq!(event.status.as_str(), "failed");
        assert!(event.answer.is_none());
        assert_eq!(
            event.error.as_ref().map(|value| value.message.as_str()),
            Some("failed to run tool")
        );
    }

    #[test]
    fn codex_status_mapping_is_supported() {
        assert_eq!(
            TurnStatus::from_codex_status("completed"),
            Some(TurnStatus::Completed)
        );
        assert_eq!(
            TurnStatus::from_codex_status("interrupted"),
            Some(TurnStatus::Interrupted)
        );
        assert_eq!(
            TurnStatus::from_codex_status("failed"),
            Some(TurnStatus::Failed)
        );
    }

    #[test]
    fn serializes_started_event_with_expected_keys() {
        let event = TurnStartedEvent::new("thread-1");
        let serialized =
            serde_json::to_value(&event).expect("turn.started event should serialize to JSON");
        assert_eq!(serialized.get("type"), None);
        assert_eq!(
            serialized.get("id"),
            Some(&Value::String("thread-1".to_string()))
        );
        assert_eq!(
            serialized.get("status"),
            Some(&Value::String("thinking".to_string()))
        );
    }

    #[test]
    fn serializes_completed_event_with_expected_keys() {
        let event = TurnCompletedEvent::new(
            "thread-2",
            TurnStatus::Completed,
            Some("Done".to_string()),
            None,
        );
        let serialized =
            serde_json::to_value(&event).expect("turn.completed event should serialize to JSON");
        assert_eq!(serialized.get("type"), None);
        assert_eq!(
            serialized.get("id"),
            Some(&Value::String("thread-2".to_string()))
        );
        assert_eq!(
            serialized.get("status"),
            Some(&Value::String("completed".to_string()))
        );
        assert_eq!(
            serialized.get("answer"),
            Some(&Value::String("Done".to_string()))
        );
        assert_eq!(serialized.get("error"), Some(&Value::Null));
    }
}
