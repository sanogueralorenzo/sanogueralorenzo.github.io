use super::{AskAdapter, AskFinalResult, command_exists, execute_headless_command};

pub struct AnthropicAskAdapter;

const ANTHROPIC_CLI_BIN: &str = "claude";

impl AskAdapter for AnthropicAskAdapter {
    fn ask(&self, prompt: &str) -> Result<AskFinalResult, String> {
        if !command_exists(ANTHROPIC_CLI_BIN) {
            return Err(format!(
                "anthropic ask requires '{}' to be installed and available on PATH",
                ANTHROPIC_CLI_BIN
            ));
        }

        execute_headless_command(ANTHROPIC_CLI_BIN, &command_args(prompt))
    }
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
