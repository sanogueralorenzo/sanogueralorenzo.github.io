use super::{AskAdapter, AskFinalResult, command_exists, execute_headless_command};

pub struct OpenAiAskAdapter;

const OPENAI_CLI_BIN: &str = "codex";

impl AskAdapter for OpenAiAskAdapter {
    fn ask(&self, prompt: &str) -> Result<AskFinalResult, String> {
        if !command_exists(OPENAI_CLI_BIN) {
            return Err(format!(
                "openai ask requires '{}' to be installed and available on PATH",
                OPENAI_CLI_BIN
            ));
        }

        execute_headless_command(OPENAI_CLI_BIN, &command_args(prompt))
    }
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
