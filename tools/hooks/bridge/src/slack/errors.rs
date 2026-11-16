use serde_json::{Value, json};

#[derive(Clone, Debug)]
pub struct HookError {
    pub code: &'static str,
    pub provider: String,
}
impl HookError {
    pub fn new(code: &str) -> Self {
        Self::from_parts(code, "Command")
    }
    pub fn from_parts(code: &str, provider: &str) -> Self {
        let code = match code {
            "auth_required" => "auth_required",
            "usage_limit" => "usage_limit",
            "permission_required" => "permission_required",
            "missing_cli" => "missing_cli",
            "timeout" => "timeout",
            "cancelled" => "cancelled",
            "invalid_response" => "invalid_response",
            "session_invalid" => "session_invalid",
            "output_limit" => "output_limit",
            "context_limit" => "context_limit",
            "workspace_missing" => "workspace_missing",
            _ => "command_failed",
        };
        Self {
            code,
            provider: if ["Codex", "Claude", "Command"].contains(&provider) {
                provider.into()
            } else {
                "Command".into()
            },
        }
    }
    pub fn from_value(value: &Value) -> Option<Self> {
        let error = value.get("error")?.as_object()?;
        Some(Self::from_parts(
            error.get("code").and_then(Value::as_str).unwrap_or(""),
            error.get("provider").and_then(Value::as_str).unwrap_or(""),
        ))
    }
    pub fn public(&self) -> Value {
        let provider = &self.provider;
        let login = match provider.as_str() {
            "Claude" => "claude auth login",
            "Codex" => "codex login",
            _ => "your CLI login command",
        };
        let message = match self.code {
            "auth_required" => format!("{provider} login expired or is missing. Run `{login}` on your computer, then send a new request."),
            "usage_limit" => format!("{provider} reached a usage or rate limit. Check your CLI account and retry later."),
            "permission_required" => format!("{provider} needs approval. Open the CLI on your computer to approve the operation, then send a new request."),
            "missing_cli" => format!("{provider} CLI was not found. Install it and run `browser-hooks install`."),
            "timeout" => format!("{provider} exceeded the command time limit. Try a smaller request or adjust timeout_seconds."),
            "cancelled" => "The request was cancelled. Send a new request when the bridge is running.".into(),
            "invalid_response" => format!("{provider} returned an invalid response. The adapter must return session_id and answer as JSON."),
            "session_invalid" => format!("{provider} could not resume this session. Start a new Slack thread."),
            "output_limit" => format!("{provider} produced too much output. Try a smaller request."),
            "context_limit" => "This thread is too large to send to the agent. Start a new Slack thread.".into(),
            "workspace_missing" => "The configured project directory no longer exists. Update workspace/projects and run `browser-hooks install`.".into(),
            _ => format!("{provider} failed. Run the CLI directly on your computer, then send a new request."),
        };
        json!({"code":self.code,"provider":provider,"message":message})
    }
}
pub type WorkResult<T> = Result<T, HookError>;
