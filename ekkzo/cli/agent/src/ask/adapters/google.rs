use super::{AskAdapter, AskFinalResult, command_exists, execute_headless_command};

pub struct GoogleAskAdapter;

const GOOGLE_CLI_BIN: &str = "gemini";

impl AskAdapter for GoogleAskAdapter {
    fn ask(&self, prompt: &str) -> Result<AskFinalResult, String> {
        if !command_exists(GOOGLE_CLI_BIN) {
            return Err(format!(
                "google ask requires '{}' to be installed and available on PATH",
                GOOGLE_CLI_BIN
            ));
        }

        execute_headless_command(GOOGLE_CLI_BIN, &command_args(prompt))
    }
}

fn command_args(prompt: &str) -> Vec<String> {
    vec![
        "-p".to_string(),
        prompt.to_string(),
        "--output-format".to_string(),
        "text".to_string(),
    ]
}

#[cfg(test)]
mod tests {
    use super::command_args;

    #[test]
    fn command_args_use_gemini_prompt() {
        let args = command_args("hello");
        assert_eq!(args[0], "-p");
        assert_eq!(args[1], "hello");
        assert_eq!(args[2], "--output-format");
        assert_eq!(args[3], "text");
    }
}
