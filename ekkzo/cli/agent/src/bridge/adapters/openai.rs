use super::BridgeAdapter;
use std::env;
use std::process::{Command, Stdio};

pub struct OpenAiBridgeAdapter;

const OPENAI_APP_SERVER_SUBCOMMAND: &str = "app-server";
const OPENAI_BIN_ENV: &str = "AGENT_OPENAI_CODEX_BIN";
const DEFAULT_OPENAI_CANDIDATES: [&str; 1] = ["codex"];

impl BridgeAdapter for OpenAiBridgeAdapter {
    fn run(&self, args: &[String]) -> Result<(), String> {
        let candidates = configured_candidates();
        let bin = resolve_openai_bin(&candidates)?;

        let mut child = Command::new(&bin)
            .arg(OPENAI_APP_SERVER_SUBCOMMAND)
            .args(args)
            .stdin(Stdio::inherit())
            .stdout(Stdio::inherit())
            .stderr(Stdio::inherit())
            .spawn()
            .map_err(|err| {
                format!("failed to start '{bin} {OPENAI_APP_SERVER_SUBCOMMAND}': {err}")
            })?;

        let status = child.wait().map_err(|err| {
            format!("failed while running '{bin} {OPENAI_APP_SERVER_SUBCOMMAND}': {err}")
        })?;

        if status.success() {
            Ok(())
        } else {
            Err(format!(
                "'{bin} {OPENAI_APP_SERVER_SUBCOMMAND}' exited with status {status}"
            ))
        }
    }
}

fn configured_candidates() -> Vec<String> {
    let mut candidates = Vec::new();
    if let Ok(value) = env::var(OPENAI_BIN_ENV) {
        let trimmed = value.trim();
        if !trimmed.is_empty() {
            candidates.push(trimmed.to_string());
        }
    }
    for candidate in DEFAULT_OPENAI_CANDIDATES {
        if !candidates.iter().any(|value| value == candidate) {
            candidates.push(candidate.to_string());
        }
    }
    candidates
}

fn resolve_openai_bin(candidates: &[String]) -> Result<String, String> {
    for candidate in candidates {
        if command_exists(candidate) {
            return Ok(candidate.clone());
        }
    }
    Err(format!(
        "openai bridge requires a codex app-server binary; looked for: {} (override with {OPENAI_BIN_ENV})",
        candidates.join(", ")
    ))
}

fn command_exists(command: &str) -> bool {
    match Command::new(command)
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
    {
        Ok(_) => true,
        Err(err) => !matches!(err.kind(), std::io::ErrorKind::NotFound),
    }
}

#[cfg(test)]
mod tests {
    use super::{configured_candidates, resolve_openai_bin};
    use std::env;

    #[test]
    fn env_candidate_is_prioritized() {
        unsafe { env::set_var("AGENT_OPENAI_CODEX_BIN", "custom-codex-bin") };
        let candidates = configured_candidates();
        unsafe { env::remove_var("AGENT_OPENAI_CODEX_BIN") };
        assert_eq!(
            candidates.first().map(String::as_str),
            Some("custom-codex-bin")
        );
    }

    #[test]
    fn resolve_returns_error_when_no_candidate_exists() {
        let candidates = vec![
            String::from("this-command-should-not-exist-1"),
            String::from("this-command-should-not-exist-2"),
        ];
        assert!(resolve_openai_bin(&candidates).is_err());
    }
}
