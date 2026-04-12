use super::{AskAdapter, AskFinalResult, command_exists, execute_headless_command};
use std::env;

pub struct AnthropicAskAdapter;

const ANTHROPIC_CLI_BIN: &str = "claude";
const ANTHROPIC_ASK_BIN_ENV: &str = "AGENT_ANTHROPIC_ASK_BIN";

impl AskAdapter for AnthropicAskAdapter {
    fn ask(&self, prompt: &str) -> Result<AskFinalResult, String> {
        let command = resolve_anthropic_bin();
        if !command_exists(&command) {
            return Err(format!(
                "anthropic ask requires '{}' to be installed and available on PATH",
                ANTHROPIC_CLI_BIN
            ));
        }

        execute_headless_command(&command, &command_args(prompt))
    }
}

fn resolve_anthropic_bin() -> String {
    env::var(ANTHROPIC_ASK_BIN_ENV).unwrap_or_else(|_| ANTHROPIC_CLI_BIN.to_string())
}

fn command_args(prompt: &str) -> Vec<String> {
    vec![
        "-p".to_string(),
        "--output-format".to_string(),
        "text".to_string(),
        prompt.to_string(),
    ]
}

#[cfg(test)]
mod tests {
    use super::command_args;

    #[test]
    fn command_args_use_claude_print() {
        let args = command_args("hello");
        assert_eq!(args[0], "-p");
        assert_eq!(args[1], "--output-format");
        assert_eq!(args[2], "text");
        assert_eq!(args[3], "hello");
    }
}
