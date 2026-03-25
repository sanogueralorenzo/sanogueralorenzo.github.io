use crate::core::events::{parse_last_agent_message_from_events, parse_thread_id_from_events};
use crate::core::process::exit_code_from_status;
use crate::core::temp::temp_file_path;
use serde::Serialize;
use std::ffi::OsString;
use std::fs;
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Command, Stdio};

enum Mode {
    Run,
    Resume,
    Review,
}

struct WrapperOptions {
    prompt_text: Option<String>,
    prompt_file: Option<PathBuf>,
    prompt_stdin: bool,
    result_json: Option<PathBuf>,
    output_last_message: Option<PathBuf>,
    emit_events: bool,
    raw_jsonl: bool,
    passthrough_args: Vec<OsString>,
}

#[derive(Serialize)]
struct ResultJson {
    status: String,
    exit_code: i32,
    thread_id: Option<String>,
    final_message: String,
    stderr: String,
}

pub fn run_from(args: Vec<OsString>) -> u8 {
    let mut iter = args.into_iter();
    let Some(command) = iter.next() else {
        print_noninteractive_command_help();
        return 0;
    };
    if command.to_string_lossy() != "noninteractive" {
        eprintln!("Internal error: expected 'noninteractive' route.");
        return 1;
    }

    let tail: Vec<OsString> = iter.collect();
    let Some(subcommand_raw) = tail.first() else {
        print_noninteractive_command_help();
        return 0;
    };
    let subcommand = subcommand_raw.to_string_lossy();
    if subcommand == "--help" || subcommand == "-h" {
        if tail.len() > 1 {
            eprintln!(
                "Unexpected arguments for noninteractive --help: {}",
                join_args(&tail[1..])
            );
            return 1;
        }
        print_noninteractive_command_help();
        return 0;
    }

    let mode = match subcommand.as_ref() {
        "run" => Mode::Run,
        "resume" => Mode::Resume,
        "review" => Mode::Review,
        other => {
            eprintln!("Unknown noninteractive command: {other}");
            return 1;
        }
    };

    let wrapper_tail = &tail[1..];
    if let Some(first) = wrapper_tail.first() {
        let value = first.to_string_lossy();
        if value == "--help" || value == "-h" {
            if wrapper_tail.len() > 1 {
                eprintln!(
                    "Unexpected arguments for noninteractive {} --help: {}",
                    mode_label(&mode),
                    join_args(&wrapper_tail[1..])
                );
                return 1;
            }
            print_noninteractive_subcommand_help(&mode);
            return 0;
        }
    }

    let options = match parse_wrapper_options(wrapper_tail) {
        Ok(options) => options,
        Err(message) => {
            eprintln!("{message}");
            return 1;
        }
    };

    run_wrapper(mode, options)
}

fn parse_wrapper_options(args: &[OsString]) -> Result<WrapperOptions, String> {
    let mut prompt_text: Option<String> = None;
    let mut prompt_file: Option<PathBuf> = None;
    let mut prompt_stdin = false;
    let mut result_json: Option<PathBuf> = None;
    let mut output_last_message: Option<PathBuf> = None;
    let mut emit_events = false;
    let mut raw_jsonl = false;
    let mut passthrough_args: Vec<OsString> = Vec::new();

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

    let prompt_mode_count = usize::from(prompt_text.is_some())
        + usize::from(prompt_file.is_some())
        + usize::from(prompt_stdin);
    if prompt_mode_count > 1 {
        return Err("Use only one of --prompt, --prompt-file, or --prompt-stdin.".to_string());
    }

    if let Some(path) = &prompt_file {
        if !path.exists() {
            return Err(format!("Prompt file not found: {}", path.display()));
        }
    }

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

fn run_wrapper(mode: Mode, options: WrapperOptions) -> u8 {
    let mut managed_output_last_message = false;
    let output_last_message = if let Some(path) = options.output_last_message.clone() {
        path
    } else {
        managed_output_last_message = true;
        temp_file_path("codex-core-last-message", "txt")
    };

    let mut command = Command::new("codex");
    command.arg("exec");
    match mode {
        Mode::Run => {}
        Mode::Resume => {
            command.arg("resume");
        }
        Mode::Review => {
            command.arg("review");
        }
    }
    command
        .arg("--json")
        .arg("--output-last-message")
        .arg(&output_last_message);

    for passthrough in &options.passthrough_args {
        command.arg(passthrough);
    }

    let mut stdin_bytes: Option<Vec<u8>> = None;
    if let Some(prompt_text) = &options.prompt_text {
        command.arg(prompt_text);
    } else if options.prompt_stdin {
        let mut buffer = Vec::new();
        if let Err(error) = std::io::stdin().read_to_end(&mut buffer) {
            eprintln!("Failed to read prompt from stdin: {error}");
            cleanup_managed_file(managed_output_last_message, &output_last_message);
            return 1;
        }
        stdin_bytes = Some(buffer);
        command.arg("-");
    } else if let Some(path) = &options.prompt_file {
        match fs::read(path) {
            Ok(contents) => {
                stdin_bytes = Some(contents);
                command.arg("-");
            }
            Err(error) => {
                eprintln!("Failed to read prompt file '{}': {error}", path.display());
                cleanup_managed_file(managed_output_last_message, &output_last_message);
                return 1;
            }
        }
    }

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

    if let Some(bytes) = stdin_bytes {
        if let Some(mut stdin) = child.stdin.take() {
            if let Err(error) = stdin.write_all(&bytes) {
                eprintln!("Failed to write prompt to codex stdin: {error}");
                cleanup_managed_file(managed_output_last_message, &output_last_message);
                return 1;
            }
        }
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

    let final_message = if options.raw_jsonl {
        String::new()
    } else {
        let from_file = fs::read_to_string(&output_last_message).unwrap_or_default();
        let text = if from_file.is_empty() {
            parse_last_agent_message_from_events(&events_text).unwrap_or_default()
        } else {
            from_file
        };
        print!("{text}");
        text
    };

    let thread_id = parse_thread_id_from_events(&events_text);

    if let Some(path) = options.result_json {
        let result = ResultJson {
            status: if exit_code == 0 {
                "completed".to_string()
            } else {
                "failed".to_string()
            },
            exit_code,
            thread_id,
            final_message: final_message.clone(),
            stderr: stderr_text.clone(),
        };
        if let Err(error) = write_result_json(&path, &result) {
            eprintln!("Failed to write result JSON '{}': {error}", path.display());
            cleanup_managed_file(managed_output_last_message, &output_last_message);
            return 1;
        }
    }

    cleanup_managed_file(managed_output_last_message, &output_last_message);

    if exit_code != 0 {
        eprintln!("codex exec failed with exit code {exit_code}");
        return u8::try_from(exit_code).unwrap_or(1);
    }

    0
}

fn cleanup_managed_file(is_managed: bool, path: &PathBuf) {
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

fn mode_label(mode: &Mode) -> &'static str {
    match mode {
        Mode::Run => "run",
        Mode::Resume => "resume",
        Mode::Review => "review",
    }
}

fn print_noninteractive_command_help() {
    println!("Usage:");
    println!("  codex-core noninteractive run|resume|review ...");
    println!();
    println!("Description:");
    println!("  Run standardized non-interactive Codex wrappers.");
    println!();
    println!("Subcommands:");
    println!("  run     Start a new codex exec turn with standardized wrapper output.");
    println!("  resume  Resume a codex exec thread with standardized wrapper output.");
    println!("  review  Run codex exec review with standardized wrapper output.");
}

fn print_noninteractive_subcommand_help(mode: &Mode) {
    match mode {
        Mode::Run => {
            println!("Usage:");
            println!(
                "  codex-core noninteractive run [wrapper-options] [-- codex-exec-options]"
            );
            println!();
            println!("Description:");
            println!("  Runs `codex exec --json` with standardized wrapper behavior.");
        }
        Mode::Resume => {
            println!("Usage:");
            println!(
                "  codex-core noninteractive resume [wrapper-options] [-- codex-exec-resume-options]"
            );
            println!();
            println!("Description:");
            println!("  Runs `codex exec resume --json` with standardized wrapper behavior.");
        }
        Mode::Review => {
            println!("Usage:");
            println!(
                "  codex-core noninteractive review [wrapper-options] [-- codex-exec-review-options]"
            );
            println!();
            println!("Description:");
            println!("  Runs `codex exec review --json` with standardized wrapper behavior.");
        }
    }
    println!();
    println!("Wrapper options:");
    println!("  --prompt <TEXT>        Prompt text");
    println!("  --prompt-file <PATH>   Read prompt from file");
    println!("  --prompt-stdin         Read prompt from stdin");
    println!("  --result-json <PATH>   Write normalized result JSON");
    println!("  -o, --output-last-message <PATH>");
    println!("                         Persist final message path (forwarded to codex)");
    println!("  --raw-jsonl            Print raw codex JSONL events to stdout");
    println!("  --emit-events          Mirror parsed JSONL events to stderr");
    println!();
    println!("Notes:");
    println!("  - Prompt options are mutually exclusive.");
    println!("  - Remaining args are forwarded to upstream `codex exec` subcommands.");
}

fn join_args(args: &[OsString]) -> String {
    args.iter()
        .map(|value| value.to_string_lossy().into_owned())
        .collect::<Vec<_>>()
        .join(" ")
}
