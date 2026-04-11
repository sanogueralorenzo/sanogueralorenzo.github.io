use serde::Serialize;

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct TurnStartedEvent {
    #[serde(rename = "type")]
    pub event_type: &'static str,
    #[serde(rename = "threadId")]
    pub thread_id: String,
    pub state: &'static str,
}

impl TurnStartedEvent {
    pub fn new(thread_id: impl Into<String>) -> Self {
        Self {
            event_type: "turn.started",
            thread_id: thread_id.into(),
            state: "in_progress",
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
    #[serde(rename = "type")]
    pub event_type: &'static str,
    #[serde(rename = "threadId")]
    pub thread_id: String,
    pub status: TurnCompletionStatus,
    pub answer: Option<String>,
    pub error: Option<TurnError>,
}

impl TurnCompletedEvent {
    pub fn new(
        thread_id: impl Into<String>,
        status: TurnCompletionStatus,
        answer: Option<String>,
        error: Option<TurnError>,
    ) -> Self {
        Self {
            event_type: "turn.completed",
            thread_id: thread_id.into(),
            status,
            answer,
            error,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum TurnCompletionStatus {
    Completed,
    Interrupted,
    Failed,
}

impl TurnCompletionStatus {
    pub fn as_str(&self) -> &'static str {
        match self {
            TurnCompletionStatus::Completed => "completed",
            TurnCompletionStatus::Interrupted => "interrupted",
            TurnCompletionStatus::Failed => "failed",
        }
    }

    pub fn from_codex_status(status: &str) -> Option<Self> {
        match status {
            "completed" => Some(TurnCompletionStatus::Completed),
            "interrupted" => Some(TurnCompletionStatus::Interrupted),
            "failed" => Some(TurnCompletionStatus::Failed),
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
    use super::{TurnCompletedEvent, TurnCompletionStatus, TurnError, TurnStartedEvent};
    use serde_json::Value;

    #[test]
    fn started_event_matches_contract() {
        let event = TurnStartedEvent::new("thread-1");
        assert_eq!(event.event_type, "turn.started");
        assert_eq!(event.thread_id, "thread-1");
        assert_eq!(event.state, "in_progress");
    }

    #[test]
    fn completed_event_matches_contract() {
        let error = TurnError::new("failed to run tool", Some(String::from("tool_failure")));
        let event =
            TurnCompletedEvent::new("thread-1", TurnCompletionStatus::Failed, None, Some(error));

        assert_eq!(event.event_type, "turn.completed");
        assert_eq!(event.thread_id, "thread-1");
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
            TurnCompletionStatus::from_codex_status("completed"),
            Some(TurnCompletionStatus::Completed)
        );
        assert_eq!(
            TurnCompletionStatus::from_codex_status("interrupted"),
            Some(TurnCompletionStatus::Interrupted)
        );
        assert_eq!(
            TurnCompletionStatus::from_codex_status("failed"),
            Some(TurnCompletionStatus::Failed)
        );
    }

    #[test]
    fn serializes_started_event_with_expected_keys() {
        let event = TurnStartedEvent::new("thread-1");
        let serialized =
            serde_json::to_value(&event).expect("turn.started event should serialize to JSON");
        assert_eq!(
            serialized.get("type"),
            Some(&Value::String("turn.started".to_string()))
        );
        assert_eq!(
            serialized.get("threadId"),
            Some(&Value::String("thread-1".to_string()))
        );
        assert_eq!(
            serialized.get("state"),
            Some(&Value::String("in_progress".to_string()))
        );
    }
}
