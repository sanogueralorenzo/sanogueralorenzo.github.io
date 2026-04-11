mod anthropic;
mod google;
mod openai;

use anthropic::AnthropicAskAdapter;
use google::GoogleAskAdapter;
use openai::OpenAiAskAdapter;

use crate::ask::contracts::{AskError, AskStatus};
use std::process::Command;

#[derive(Debug)]
pub struct AskFinalResult {
    pub status: AskStatus,
    pub answer: Option<String>,
    pub error: Option<AskError>,
}

pub trait AskAdapter {
    fn ask(&self, prompt: &str) -> Result<AskFinalResult, String>;
}

pub fn ask_with_provider(provider_name: &str, prompt: &str) -> Result<AskFinalResult, String> {
    match provider_name {
        "openai" => OpenAiAskAdapter.ask(prompt),
        "anthropic" => AnthropicAskAdapter.ask(prompt),
        "google" => GoogleAskAdapter.ask(prompt),
        _ => Err(format!("unknown provider '{provider_name}'")),
    }
}

pub(super) fn execute_headless_command(
    command: &str,
    args: &[String],
) -> Result<AskFinalResult, String> {
    let output = Command::new(command)
        .args(args)
        .output()
        .map_err(|err| format!("failed running '{command} {}': {err}", args.join(" ")))?;

    let stdout = normalize_output(&output.stdout);
    let stderr = normalize_output(&output.stderr);

    if output.status.success() {
        return Ok(AskFinalResult {
            status: AskStatus::Completed,
            answer: if stdout.is_empty() {
                None
            } else {
                Some(stdout)
            },
            error: None,
        });
    }

    let exit_code = output.status.code().unwrap_or(1);
    if exit_code == 130 {
        return Ok(AskFinalResult {
            status: AskStatus::Interrupted,
            answer: None,
            error: if stderr.is_empty() {
                None
            } else {
                Some(AskError::new(stderr, Some(exit_code.to_string())))
            },
        });
    }

    let message = if !stderr.is_empty() {
        stderr
    } else if !stdout.is_empty() {
        stdout
    } else {
        format!("command exited with status {exit_code}")
    };

    Ok(AskFinalResult {
        status: AskStatus::Failed,
        answer: None,
        error: Some(AskError::new(message, Some(exit_code.to_string()))),
    })
}

pub(super) fn command_exists(command: &str) -> bool {
    match Command::new(command).arg("--version").output() {
        Ok(_) => true,
        Err(err) => !matches!(err.kind(), std::io::ErrorKind::NotFound),
    }
}

fn normalize_output(bytes: &[u8]) -> String {
    String::from_utf8_lossy(bytes).trim().to_string()
}

#[cfg(test)]
mod tests {
    use super::{AskStatus, ask_with_provider, execute_headless_command};

    #[test]
    fn unknown_provider_is_rejected() {
        let err = ask_with_provider("unknown", "hello").expect_err("provider should fail");
        assert!(err.contains("unknown provider"));
    }

    #[test]
    fn successful_process_maps_to_completed() {
        let args = vec!["-c".to_string(), "printf 'done'".to_string()];
        let result = execute_headless_command("/bin/sh", &args).expect("command should run");
        assert_eq!(result.status, AskStatus::Completed);
        assert_eq!(result.answer.as_deref(), Some("done"));
        assert!(result.error.is_none());
    }

    #[test]
    fn interrupted_process_maps_to_interrupted() {
        let args = vec![
            "-c".to_string(),
            "echo cancelled 1>&2; exit 130".to_string(),
        ];
        let result = execute_headless_command("/bin/sh", &args).expect("command should run");
        assert_eq!(result.status, AskStatus::Interrupted);
        assert!(result.answer.is_none());
        assert_eq!(
            result
                .error
                .as_ref()
                .and_then(|value| value.code.as_deref()),
            Some("130")
        );
    }

    #[test]
    fn failed_process_maps_to_failed() {
        let args = vec!["-c".to_string(), "echo boom 1>&2; exit 7".to_string()];
        let result = execute_headless_command("/bin/sh", &args).expect("command should run");
        assert_eq!(result.status, AskStatus::Failed);
        assert!(result.answer.is_none());
        assert_eq!(
            result
                .error
                .as_ref()
                .and_then(|value| value.code.as_deref()),
            Some("7")
        );
    }
}
