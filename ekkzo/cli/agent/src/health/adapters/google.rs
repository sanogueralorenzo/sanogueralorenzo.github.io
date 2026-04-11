use super::{CommandResult, HealthAdapter, run_command};
use crate::health::contracts::{HealthState, ProviderHealth};
use serde_json::Value;
use std::env;
use std::fs;
use std::path::PathBuf;

pub struct GoogleHealthAdapter;

impl HealthAdapter for GoogleHealthAdapter {
    fn check(&self) -> ProviderHealth {
        let version_result = run_command("gemini", &["--version"]);
        from_health_checks("google", "gemini --version + ~/.gemini/google_accounts.json", version_result)
    }
}

fn from_health_checks(provider: &str, method: &str, version_result: CommandResult) -> ProviderHealth {
    match version_result {
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
        CommandResult::Output(_) => {
            let (authenticated, auth_detail) = read_google_accounts_state();
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
                detail: auth_detail,
            }
        }
    }
}

fn read_google_accounts_state() -> (bool, String) {
    let Some(path) = google_accounts_path() else {
        return (false, "HOME is not set".to_string());
    };

    let content = match fs::read_to_string(&path) {
        Ok(value) => value,
        Err(err) => return (false, format!("failed reading {}: {err}", path.display())),
    };

    let value: Value = match serde_json::from_str(&content) {
        Ok(value) => value,
        Err(err) => return (false, format!("invalid json in {}: {err}", path.display())),
    };

    let active = value
        .get("active")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string();
    if active.is_empty() {
        return (false, "no active Google account configured".to_string());
    }

    (true, format!("active account: {active}"))
}

fn google_accounts_path() -> Option<PathBuf> {
    let home = env::var("HOME").ok()?;
    Some(PathBuf::from(home).join(".gemini").join("google_accounts.json"))
}

#[cfg(test)]
mod tests {
    use super::google_accounts_path;

    #[test]
    fn google_accounts_path_uses_home() {
        assert!(google_accounts_path().is_some());
    }
}
