mod anthropic;
mod google;
mod openai;

use crate::health::contracts::{HealthReport, HealthState, ProviderHealth};
use anthropic::AnthropicHealthAdapter;
use google::GoogleHealthAdapter;
use openai::OpenAiHealthAdapter;
use std::process::Command;

pub trait HealthAdapter {
    fn check(&self) -> ProviderHealth;
}

pub struct CommandOutput {
    pub stdout: String,
    pub stderr: String,
    pub success: bool,
}

pub enum CommandResult {
    Output(CommandOutput),
    MissingBinary,
    CommandError(String),
}

pub fn collect_health_report() -> HealthReport {
    let providers = vec![
        OpenAiHealthAdapter.check(),
        AnthropicHealthAdapter.check(),
        GoogleHealthAdapter.check(),
    ];

    let status = overall_status(&providers);
    HealthReport { status, providers }
}

pub(crate) fn run_command(binary: &str, args: &[&str]) -> CommandResult {
    match Command::new(binary).args(args).output() {
        Ok(output) => CommandResult::Output(CommandOutput {
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            stderr: String::from_utf8_lossy(&output.stderr).to_string(),
            success: output.status.success(),
        }),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => CommandResult::MissingBinary,
        Err(err) => CommandResult::CommandError(err.to_string()),
    }
}

fn overall_status(providers: &[ProviderHealth]) -> HealthState {
    if providers
        .iter()
        .any(|provider| provider.status == HealthState::Unhealthy)
    {
        return HealthState::Unhealthy;
    }

    if providers
        .iter()
        .any(|provider| provider.status == HealthState::Degraded)
    {
        return HealthState::Degraded;
    }

    HealthState::Healthy
}

#[cfg(test)]
mod tests {
    use super::overall_status;
    use crate::health::contracts::{HealthState, ProviderHealth};

    #[test]
    fn overall_status_is_unhealthy_if_any_provider_is_unhealthy() {
        let providers = vec![
            ProviderHealth {
                provider: "openai".to_string(),
                status: HealthState::Healthy,
                cli_available: true,
                authenticated: true,
                check_method: "test".to_string(),
                detail: "ok".to_string(),
            },
            ProviderHealth {
                provider: "google".to_string(),
                status: HealthState::Unhealthy,
                cli_available: false,
                authenticated: false,
                check_method: "test".to_string(),
                detail: "missing".to_string(),
            },
        ];

        assert_eq!(overall_status(&providers), HealthState::Unhealthy);
    }
}
