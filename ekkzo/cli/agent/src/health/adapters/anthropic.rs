use super::{CommandResult, HealthAdapter, run_command};
use crate::health::contracts::{ProviderHealth, ProviderHealthStatus};
use serde_json::Value;

pub struct AnthropicHealthAdapter;

impl HealthAdapter for AnthropicHealthAdapter {
    fn check(&self) -> ProviderHealth {
        let result = run_command("claude", &["auth", "status"]);
        from_command_result("anthropic", result)
    }
}

fn from_command_result(provider: &str, result: CommandResult) -> ProviderHealth {
    match result {
        CommandResult::MissingBinary => ProviderHealth {
            provider: provider.to_string(),
            status: ProviderHealthStatus::CliMissing,
        },
        CommandResult::CommandError => ProviderHealth {
            provider: provider.to_string(),
            status: ProviderHealthStatus::AuthMissing,
        },
        CommandResult::Output(output) => {
            let authenticated = parse_logged_in_status(&output.stdout, output.success);
            ProviderHealth {
                provider: provider.to_string(),
                status: if authenticated {
                    ProviderHealthStatus::Connected
                } else {
                    ProviderHealthStatus::AuthMissing
                },
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
