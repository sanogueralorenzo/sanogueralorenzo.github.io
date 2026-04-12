use super::{AskAdapter, AskFinalResult, command_exists, execute_headless_command};
use std::env;

pub struct OpenAiAskAdapter;

const OPENAI_CLI_BIN: &str = "codex";
const OPENAI_ASK_BIN_ENV: &str = "AGENT_OPENAI_ASK_BIN";

impl AskAdapter for OpenAiAskAdapter {
    fn ask(&self, prompt: &str) -> Result<AskFinalResult, String> {
        let command = resolve_openai_bin();
        if !command_exists(&command) {
            return Err(format!(
                "openai ask requires '{}' to be installed and available on PATH",
                OPENAI_CLI_BIN
            ));
        }

        execute_headless_command(&command, &command_args(prompt))
    }
}

fn resolve_openai_bin() -> String {
    env::var(OPENAI_ASK_BIN_ENV).unwrap_or_else(|_| OPENAI_CLI_BIN.to_string())
}

fn command_args(prompt: &str) -> Vec<String> {
    vec![
        "exec".to_string(),
        "--color".to_string(),
        "never".to_string(),
        prompt.to_string(),
    ]
}

#[cfg(test)]
mod tests {
    use super::command_args;

    #[test]
    fn command_args_use_codex_exec() {
        let args = command_args("hello");
        assert_eq!(args[0], "exec");
        assert_eq!(args[1], "--color");
        assert_eq!(args[2], "never");
        assert_eq!(args[3], "hello");
    }
}
