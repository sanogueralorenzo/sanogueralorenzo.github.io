use super::{CommandResult, HealthAdapter, run_command};
use crate::health::contracts::{HealthState, ProviderHealth};

pub struct OpenAiHealthAdapter;

impl HealthAdapter for OpenAiHealthAdapter {
    fn check(&self) -> ProviderHealth {
        let result = run_command("codex", &["login", "status"]);
        from_command_result("openai", "codex login status", result)
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
    let normalized = stdout.to_lowercase();
    if normalized.contains("not logged in")
        || normalized.contains("logged out")
        || normalized.contains("\"loggedin\":false")
    {
        return false;
    }

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
    use super::{parse_logged_in_status, summarize_output};

    #[test]
    fn parse_logged_in_status_detects_logged_in_text() {
        assert!(parse_logged_in_status("Logged in using ChatGPT", true));
    }

    #[test]
    fn parse_logged_in_status_detects_logged_out() {
        assert!(!parse_logged_in_status("Not logged in", false));
    }

    #[test]
    fn summarize_output_prefers_stdout() {
        assert_eq!(summarize_output("hello\n", "ignored\n"), "hello");
    }
}
