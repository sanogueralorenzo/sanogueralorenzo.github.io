use crate::noninteractive::cli::WrapperOptions;
use std::path::Path;
use std::process::Command;

pub fn build_codex_command(
    mode: &str,
    options: &WrapperOptions,
    output_last_message: &Path,
) -> Command {
    let mut command = Command::new("codex");
    command.arg("exec");

    match mode {
        "run" => {}
        "resume" => {
            command.arg("resume");
        }
        "review" => {
            command.arg("review");
        }
        _ => {}
    }

    command
        .arg("--json")
        .arg("--output-last-message")
        .arg(output_last_message);

    for passthrough in &options.passthrough_args {
        command.arg(passthrough);
    }

    if let Some(prompt_text) = &options.prompt_text {
        command.arg(prompt_text);
    } else if options.prompt_stdin || options.prompt_file.is_some() {
        command.arg("-");
    }

    command
}

#[cfg(test)]
mod tests {
    use super::build_codex_command;
    use crate::noninteractive::cli::WrapperOptions;
    use std::ffi::OsString;
    use std::path::Path;

    #[test]
    fn review_mode_appends_review_subcommand() {
        let command = build_codex_command(
            "review",
            &WrapperOptions {
                prompt_text: Some("check this".to_string()),
                prompt_file: None,
                prompt_stdin: false,
                result_json: None,
                output_last_message: None,
                emit_events: false,
                raw_jsonl: false,
                passthrough_args: vec![OsString::from("--model"), OsString::from("gpt-5.4")],
            },
            Path::new("/tmp/last-message.txt"),
        );

        let args = command.get_args().collect::<Vec<_>>();
        assert_eq!(args[0], "exec");
        assert_eq!(args[1], "review");
    }
}
