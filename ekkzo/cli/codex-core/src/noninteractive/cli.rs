use std::ffi::OsString;
use std::path::PathBuf;

#[derive(Debug, Clone)]
pub struct WrapperOptions {
    pub prompt_text: Option<String>,
    pub prompt_file: Option<PathBuf>,
    pub prompt_stdin: bool,
    pub result_json: Option<PathBuf>,
    pub output_last_message: Option<PathBuf>,
    pub emit_events: bool,
    pub raw_jsonl: bool,
    pub passthrough_args: Vec<OsString>,
}

pub fn parse_wrapper_options(args: &[OsString]) -> Result<WrapperOptions, String> {
    let mut prompt_text: Option<String> = None;
    let mut prompt_file: Option<PathBuf> = None;
    let mut prompt_stdin = false;
    let mut result_json: Option<PathBuf> = None;
    let mut output_last_message: Option<PathBuf> = None;
    let mut emit_events = false;
    let mut raw_jsonl = false;
    let mut passthrough_args = Vec::new();

    let mut index = 0usize;
    while index < args.len() {
        let token = &args[index];
        let label = token.to_string_lossy();

        match label.as_ref() {
            "--prompt" => {
                let Some(value) = args.get(index + 1) else {
                    return Err("Missing value for --prompt".to_string());
                };
                prompt_text = Some(value.to_string_lossy().into_owned());
                index += 2;
            }
            "--prompt-file" => {
                let Some(value) = args.get(index + 1) else {
                    return Err("Missing value for --prompt-file".to_string());
                };
                prompt_file = Some(PathBuf::from(value));
                index += 2;
            }
            "--prompt-stdin" => {
                prompt_stdin = true;
                index += 1;
            }
            "--result-json" => {
                let Some(value) = args.get(index + 1) else {
                    return Err("Missing value for --result-json".to_string());
                };
                result_json = Some(PathBuf::from(value));
                index += 2;
            }
            "--output-last-message" | "-o" => {
                let Some(value) = args.get(index + 1) else {
                    return Err(format!("Missing value for {label}"));
                };
                output_last_message = Some(PathBuf::from(value));
                index += 2;
            }
            "--emit-events" => {
                emit_events = true;
                index += 1;
            }
            "--raw-jsonl" => {
                raw_jsonl = true;
                index += 1;
            }
            "--" => {
                passthrough_args.extend_from_slice(&args[index + 1..]);
                break;
            }
            _ => {
                passthrough_args.push(token.clone());
                index += 1;
            }
        }
    }

    validate_prompt_inputs(&prompt_text, &prompt_file, prompt_stdin)?;

    Ok(WrapperOptions {
        prompt_text,
        prompt_file,
        prompt_stdin,
        result_json,
        output_last_message,
        emit_events,
        raw_jsonl,
        passthrough_args,
    })
}

fn validate_prompt_inputs(
    prompt_text: &Option<String>,
    prompt_file: &Option<PathBuf>,
    prompt_stdin: bool,
) -> Result<(), String> {
    let prompt_mode_count = usize::from(prompt_text.is_some())
        + usize::from(prompt_file.is_some())
        + usize::from(prompt_stdin);
    if prompt_mode_count > 1 {
        return Err("Use only one of --prompt, --prompt-file, or --prompt-stdin.".to_string());
    }

    if let Some(path) = prompt_file
        && !path.exists()
    {
        return Err(format!("Prompt file not found: {}", path.display()));
    }

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::parse_wrapper_options;
    use std::ffi::OsString;

    #[test]
    fn parses_wrapper_options_and_passthrough() {
        let args = vec![
            OsString::from("--prompt"),
            OsString::from("hello"),
            OsString::from("--emit-events"),
            OsString::from("--"),
            OsString::from("--model"),
            OsString::from("gpt-5.4"),
        ];

        let options = parse_wrapper_options(&args).unwrap();
        assert_eq!(options.prompt_text.as_deref(), Some("hello"));
        assert!(options.emit_events);
        assert_eq!(options.passthrough_args.len(), 2);
    }

    #[test]
    fn rejects_multiple_prompt_sources() {
        let args = vec![
            OsString::from("--prompt"),
            OsString::from("hello"),
            OsString::from("--prompt-stdin"),
        ];

        let error = parse_wrapper_options(&args).unwrap_err();
        assert_eq!(
            error,
            "Use only one of --prompt, --prompt-file, or --prompt-stdin."
        );
    }
}
