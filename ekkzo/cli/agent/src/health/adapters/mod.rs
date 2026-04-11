mod anthropic;
mod google;
mod openai;

use crate::health::contracts::{HealthReport, ProviderHealth};
use anthropic::AnthropicHealthAdapter;
use google::GoogleHealthAdapter;
use openai::OpenAiHealthAdapter;
use std::process::Command;

pub trait HealthAdapter {
    fn check(&self) -> ProviderHealth;
}

pub struct CommandOutput {
    pub stdout: String,
    pub success: bool,
}

pub enum CommandResult {
    Output(CommandOutput),
    MissingBinary,
    CommandError,
}

pub fn collect_health_report() -> HealthReport {
    let providers = vec![
        OpenAiHealthAdapter.check(),
        AnthropicHealthAdapter.check(),
        GoogleHealthAdapter.check(),
    ];
    HealthReport { providers }
}

pub(crate) fn run_command(binary: &str, args: &[&str]) -> CommandResult {
    match Command::new(binary).args(args).output() {
        Ok(output) => CommandResult::Output(CommandOutput {
            stdout: String::from_utf8_lossy(&output.stdout).to_string(),
            success: output.status.success(),
        }),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => CommandResult::MissingBinary,
        Err(_) => CommandResult::CommandError,
    }
}

#[cfg(test)]
mod tests {
    use super::collect_health_report;
    use crate::health::contracts::ProviderHealthStatus;

    #[test]
    fn report_contains_three_known_providers() {
        let report = collect_health_report();
        assert_eq!(report.providers.len(), 3);
        assert!(report.providers.iter().any(|value| value.provider == "openai"));
        assert!(
            report
                .providers
                .iter()
                .any(|value| value.status == ProviderHealthStatus::CliMissing
                    || value.status == ProviderHealthStatus::AuthMissing
                    || value.status == ProviderHealthStatus::Connected)
        );
    }
}
