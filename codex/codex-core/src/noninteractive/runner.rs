use crate::core::events::{parse_last_agent_message_from_events, parse_thread_id_from_events};
use crate::core::process::exit_code_from_status;
use crate::core::temp::temp_file_path;
use crate::noninteractive::cli::WrapperOptions;
use serde::Serialize;
use std::fs;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

#[derive(Serialize)]
struct ResultJson {
    status: String,
    exit_code: i32,
    thread_id: Option<String>,
    final_message: String,
    stderr: String,
}

pub fn run_wrapper(mode: &str, options: WrapperOptions) -> u8 {
    let mut managed_output_last_message = false;
    let output_last_message = if let Some(path) = options.output_last_message.clone() {
        path
    } else {
        managed_output_last_message = true;
        temp_file_path("codex-core-last-message", "txt")
    };

    let mut command = build_codex_command(mode, &options, &output_last_message);
    let stdin_bytes =
        match load_prompt_bytes(&options, managed_output_last_message, &output_last_message) {
            Ok(stdin_bytes) => stdin_bytes,
            Err(exit_code) => return exit_code,
        };

    if stdin_bytes.is_some() {
        command.stdin(Stdio::piped());
    }
    command.stdout(Stdio::piped());
    command.stderr(Stdio::piped());

    let mut child = match command.spawn() {
        Ok(child) => child,
        Err(error) => {
            if error.kind() == std::io::ErrorKind::NotFound {
                eprintln!("Missing 'codex' CLI in PATH.");
            } else {
                eprintln!("Failed to launch codex exec: {error}");
            }
            cleanup_managed_file(managed_output_last_message, &output_last_message);
            return 1;
        }
    };

    if let Some(bytes) = stdin_bytes
        && let Some(mut stdin) = child.stdin.take()
        && let Err(error) = stdin.write_all(&bytes)
    {
        eprintln!("Failed to write prompt to codex stdin: {error}");
        cleanup_managed_file(managed_output_last_message, &output_last_message);
        return 1;
    }

    let output = match child.wait_with_output() {
        Ok(output) => output,
        Err(error) => {
            eprintln!("Failed waiting for codex exec: {error}");
            cleanup_managed_file(managed_output_last_message, &output_last_message);
            return 1;
        }
    };

    let exit_code = i32::from(exit_code_from_status(&output.status));
    let events_text = String::from_utf8_lossy(&output.stdout).to_string();
    let stderr_text = String::from_utf8_lossy(&output.stderr).to_string();

    if !stderr_text.is_empty() {
        eprint!("{stderr_text}");
    }
    if options.emit_events {
        eprint!("{events_text}");
    }
    if options.raw_jsonl {
        print!("{events_text}");
    }

    let final_message = render_final_message(&options, &events_text, &output_last_message);
    let thread_id = parse_thread_id_from_events(&events_text);

    if let Some(path) = options.result_json
        && let Err(error) = write_result_json(
            &path,
            &ResultJson {
                status: if exit_code == 0 {
                    "completed".to_string()
                } else {
                    "failed".to_string()
                },
                exit_code,
                thread_id,
                final_message: final_message.clone(),
                stderr: stderr_text.clone(),
            },
        )
    {
        eprintln!("Failed to write result JSON '{}': {error}", path.display());
        cleanup_managed_file(managed_output_last_message, &output_last_message);
        return 1;
    }

    cleanup_managed_file(managed_output_last_message, &output_last_message);

    if exit_code != 0 {
        eprintln!("codex exec failed with exit code {exit_code}");
        return u8::try_from(exit_code).unwrap_or(1);
    }

    0
}

fn build_codex_command(
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

fn load_prompt_bytes(
    options: &WrapperOptions,
    managed_output_last_message: bool,
    output_last_message: &Path,
) -> Result<Option<Vec<u8>>, u8> {
    if options.prompt_stdin {
        let mut buffer = Vec::new();
        if let Err(error) = std::io::stdin().read_to_end(&mut buffer) {
            eprintln!("Failed to read prompt from stdin: {error}");
            cleanup_managed_file(managed_output_last_message, output_last_message);
            return Err(1);
        }
        return Ok(Some(buffer));
    }

    let Some(path) = &options.prompt_file else {
        return Ok(None);
    };

    match fs::read(path) {
        Ok(contents) => Ok(Some(contents)),
        Err(error) => {
            eprintln!("Failed to read prompt file '{}': {error}", path.display());
            cleanup_managed_file(managed_output_last_message, output_last_message);
            Err(1)
        }
    }
}

fn render_final_message(
    options: &WrapperOptions,
    events_text: &str,
    output_last_message: &Path,
) -> String {
    if options.raw_jsonl {
        return String::new();
    }

    let from_file = fs::read_to_string(output_last_message).unwrap_or_default();
    let text = if from_file.is_empty() {
        parse_last_agent_message_from_events(events_text).unwrap_or_default()
    } else {
        from_file
    };
    print!("{text}");
    text
}

fn cleanup_managed_file(is_managed: bool, path: &Path) {
    if is_managed {
        let _ = fs::remove_file(path);
    }
}

fn write_result_json(path: &PathBuf, result: &ResultJson) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let serialized = serde_json::to_string_pretty(result)
        .map_err(|error| std::io::Error::other(error.to_string()))?;
    fs::write(path, format!("{serialized}\n"))
}
