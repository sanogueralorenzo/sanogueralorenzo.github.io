use super::{CommandResult, HealthAdapter, run_command};
use crate::health::contracts::{ProviderHealth, ProviderHealthStatus};
use serde_json::Value;
use std::env;
use std::fs;
use std::path::PathBuf;

pub struct GoogleHealthAdapter;

impl HealthAdapter for GoogleHealthAdapter {
    fn check(&self) -> ProviderHealth {
        let version_result = run_command("gemini", &["--version"]);
        from_health_checks("google", version_result)
    }
}

fn from_health_checks(provider: &str, version_result: CommandResult) -> ProviderHealth {
    match version_result {
        CommandResult::MissingBinary => ProviderHealth {
            provider: provider.to_string(),
            status: ProviderHealthStatus::CliMissing,
        },
        CommandResult::CommandError => ProviderHealth {
            provider: provider.to_string(),
            status: ProviderHealthStatus::AuthMissing,
        },
        CommandResult::Output(_) => {
            let authenticated = read_google_accounts_state();
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

fn read_google_accounts_state() -> bool {
    let Some(path) = google_accounts_path() else {
        return false;
    };

    let content = match fs::read_to_string(&path) {
        Ok(value) => value,
        Err(_) => return false,
    };

    let value: Value = match serde_json::from_str(&content) {
        Ok(value) => value,
        Err(_) => return false,
    };

    let active = value
        .get("active")
        .and_then(Value::as_str)
        .unwrap_or("")
        .trim()
        .to_string();
    if active.is_empty() {
        return false;
    }

    true
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
