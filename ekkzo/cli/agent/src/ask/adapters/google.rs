use super::{AskAdapter, AskFinalResult, command_exists, execute_headless_command};
use std::env;

pub struct GoogleAskAdapter;

const GOOGLE_CLI_BIN: &str = "gemini";
const GOOGLE_ASK_BIN_ENV: &str = "AGENT_GOOGLE_ASK_BIN";

impl AskAdapter for GoogleAskAdapter {
    fn ask(&self, prompt: &str) -> Result<AskFinalResult, String> {
        let command = resolve_google_bin();
        if !command_exists(&command) {
            return Err(format!(
                "google ask requires '{}' to be installed and available on PATH",
                GOOGLE_CLI_BIN
            ));
        }

        execute_headless_command(&command, &command_args(prompt))
    }
}

fn resolve_google_bin() -> String {
    env::var(GOOGLE_ASK_BIN_ENV).unwrap_or_else(|_| GOOGLE_CLI_BIN.to_string())
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
