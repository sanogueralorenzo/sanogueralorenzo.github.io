use super::{CommandResult, HealthAdapter, run_command};
use crate::health::contracts::{ProviderHealth, ProviderHealthStatus};

pub struct OpenAiHealthAdapter;

impl HealthAdapter for OpenAiHealthAdapter {
    fn check(&self) -> ProviderHealth {
        let result = run_command("codex", &["login", "status"]);
        from_command_result("openai", result)
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

#[cfg(test)]
mod tests {
    use super::parse_logged_in_status;

    #[test]
    fn parse_logged_in_status_detects_logged_in_text() {
        assert!(parse_logged_in_status("Logged in using ChatGPT", true));
    }

    #[test]
    fn parse_logged_in_status_detects_logged_out() {
        assert!(!parse_logged_in_status("Not logged in", false));
    }

}
