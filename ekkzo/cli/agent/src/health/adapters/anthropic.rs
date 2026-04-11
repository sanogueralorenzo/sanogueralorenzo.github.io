use super::{CommandResult, HealthAdapter, run_command};
use crate::health::contracts::{HealthState, ProviderHealth};
use serde_json::Value;

pub struct AnthropicHealthAdapter;

impl HealthAdapter for AnthropicHealthAdapter {
    fn check(&self) -> ProviderHealth {
        let result = run_command("claude", &["auth", "status"]);
        from_command_result("anthropic", "claude auth status", result)
    }
}

fn from_command_result(provider: &str, method: &str, result: CommandResult) -> ProviderHealth {
    match result {
        CommandResult::MissingBinary => ProviderHealth {
            provider: provider.to_string(),
            status: HealthState::Unhealthy,
            cli_available: false,
            authenticated: false,
            check_method: method.to_string(),
            detail: "binary not found on PATH".to_string(),
        },
        CommandResult::CommandError(message) => ProviderHealth {
            provider: provider.to_string(),
            status: HealthState::Unhealthy,
            cli_available: true,
            authenticated: false,
            check_method: method.to_string(),
            detail: message,
        },
        CommandResult::Output(output) => {
            let authenticated = parse_logged_in_status(&output.stdout, output.success);
            ProviderHealth {
                provider: provider.to_string(),
                status: if authenticated {
                    HealthState::Healthy
                } else {
                    HealthState::Degraded
                },
                cli_available: true,
                authenticated,
                check_method: method.to_string(),
                detail: summarize_output(&output.stdout, &output.stderr),
            }
        }
    }
}

fn parse_logged_in_status(stdout: &str, success: bool) -> bool {
    if let Ok(value) = serde_json::from_str::<Value>(stdout) {
        if let Some(logged_in) = value.get("loggedIn").and_then(Value::as_bool) {
            return logged_in;
        }
    }

    let normalized = stdout.to_lowercase();
    normalized.contains("logged in")
        || normalized.contains("authenticated")
        || normalized.contains("\"loggedin\":true")
        || success
}

fn summarize_output(stdout: &str, stderr: &str) -> String {
    if !stdout.trim().is_empty() {
        return stdout.trim().to_string();
    }
    if !stderr.trim().is_empty() {
        return stderr.trim().to_string();
    }
    "no output".to_string()
}

#[cfg(test)]
mod tests {
    use super::parse_logged_in_status;

    #[test]
    fn parse_logged_in_status_reads_json_field() {
        assert!(parse_logged_in_status(r#"{"loggedIn":true}"#, false));
        assert!(!parse_logged_in_status(r#"{"loggedIn":false}"#, true));
    }

    #[test]
    fn parse_logged_in_status_falls_back_to_text() {
        assert!(parse_logged_in_status("Authenticated", false));
    }
}
